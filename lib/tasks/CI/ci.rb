
module CombinationIndex
  input :blue_doses, :array, "Blue doses"
  input :blue_responses, :array, "Blue doses"
  input :red_doses, :array, "Red doses"
  input :red_responses, :array, "Red doses"
  input :blue_dose, :float, "Blue combination dose"
  input :red_dose, :float, "Blue combination dose"
  input :response, :float, "Combination response"
  input :fix_ratio, :boolean, "Fix combination ratio dose", false
  input :model_type, :select, "Model type for the DRC fit", "least_squares", :select_options => ["least_squares", "LL.2", "LL.3", "LL.4", "LL.5"]
  input :more_doses, :array, "More combination dose"
  input :more_responses, :array, "More combination responses"
  input :direct_ci, :boolean, "Compute CI directly from model instead of through ME points (for models other than least squares)", false
  extension :svg
  dep :compute => :produce do |jobname, options|
    model_type = options[:model_type]

    if jobname.include? "-"
      blue_drug, red_drug = jobname.split("-")
    else
      blue_drug = red_drug = jobname
    end

    if model_type.to_s =~ /least_squares/
      median_point = 0.5
    else
      median_point = options[:response].to_f
    end

    [
      CombinationIndex.job(:fit, blue_drug, :doses => options[:blue_doses].collect{|v| v.to_f}, :responses => options[:blue_responses].collect{|v| v.to_f}, :median_point => median_point.to_f, :model_type => model_type),
      CombinationIndex.job(:fit, red_drug, :doses => options[:red_doses].collect{|v| v.to_f}, :responses => options[:red_responses].collect{|v| v.to_f}, :median_point => median_point.to_f, :model_type => model_type)
    ]
  end
  task :ci => :text do |blue_doses,blue_responses,red_doses,red_responses,blue_dose,red_dose,response,fix_ratio,model_type,more_doses,more_responses, direct_ci|
    blue_step, red_step = dependencies
    blue_doses = blue_doses.collect{|v| v.to_f}
    blue_responses = blue_responses.collect{|v| v.to_f}
    red_doses = red_doses.collect{|v| v.to_f}
    red_responses = red_responses.collect{|v| v.to_f}
    blue_random_samples = blue_step.info[:random_samples] || []
    red_random_samples = red_step.info[:random_samples] || []

    blue_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    blue_doses.zip(blue_responses).each do |dose, response|
      blue_tsv[Misc.hash2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    red_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    red_doses.zip(red_responses).each do |dose, response|
      red_tsv[Misc.hash2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    blue_m, blue_dm, blue_dose_1, blue_response_1, blue_dose_2, blue_response_2, blue_invert  = blue_step.info.values_at :m, :dm, :dose1, :response1, :dose2, :response2, :invert
    blue_modelfile = blue_step.file(:model)
    blue_modelfile = nil unless blue_modelfile.exists?

    red_m, red_dm, red_dose_1, red_response_1, red_dose_2, red_response_2, red_invert  = red_step.info.values_at :m, :dm, :dose1, :response1, :dose2, :response2, :invert
    red_modelfile = red_step.file(:model)
    red_modelfile = nil unless red_modelfile.exists?

    lss = true if model_type =~ /least_squares/

    if Float === blue_dm and Float === red_dm
      if lss or not direct_ci
        ci = CombinationIndex.ci_value(blue_dose, blue_dm, blue_m, red_dose, red_dm, red_m, response)
        random_doses = []
        random_ci = []

        blue_random_samples.zip(red_random_samples).collect do |bi,ri|
          next if bi.nil? or ri.nil?
          rblue_m, rblue_dm = bi
          rred_m, rred_dm = ri
          rci = CombinationIndex.ci_value(blue_dose, rblue_dm, rblue_m, red_dose, rred_dm, rred_m, response)
          random_ci << rci
        end

        set_info :CI, ci
        begin
          set_info :random_CI, random_ci.sort.reject{|ci| ci.to_s == "Infinity"}
        rescue Exception
          set_info :random_CI, []
        end
        set_info :GI50, CombinationIndex.additive_dose(0.5, blue_dose, red_dose, blue_m, blue_dm, red_m, red_dm)
      else
        ci, fit_dose_d1, fit_dose_d2 = CombinationIndex.ci_value_fit(blue_dose, red_dose, response, R::Model.load(blue_modelfile), R::Model.load(red_modelfile), blue_m < 0, red_m < 0)
        random_doses = []
        random_ci = []

        blue_random_samples.zip(red_random_samples).collect do |bi,ri|
          next if bi.nil? or ri.nil?
          rblue_m, rblue_dm = bi
          rred_m, rred_dm = ri
          rci = CombinationIndex.ci_value(blue_dose, rblue_dm, rblue_m, red_dose, rred_dm, rred_m, response)
          random_ci << rci
        end

        set_info :fit_dose_d1, fit_dose_d1
        set_info :fit_dose_d2, fit_dose_d2
        set_info :CI, ci
        set_info :random_CI, random_ci.sort.reject{|ci| ci.to_s == "Infinity"}
        set_info :GI50, CombinationIndex.additive_dose(0.5, blue_dose, red_dose, blue_m, blue_dm, red_m, red_dm)
      end
    else
      set_info :CI, nil
    end

    log :CI_plot, "Drawing CI plot"
    svg = TmpFile.with_file do |blue_data|
      Open.write(blue_data, blue_tsv.to_s)
      TmpFile.with_file do |red_data|
        Open.write(red_data, red_tsv.to_s)

        plot_script =<<-EOF
          blue_m = #{R.ruby2R blue_m}
          blue_dm = #{R.ruby2R blue_dm}
          blue_dose = #{R.ruby2R blue_dose}

          red_m = #{R.ruby2R red_m}
          red_dm = #{R.ruby2R red_dm}
          red_dose = #{R.ruby2R red_dose}

          response = #{R.ruby2R response}

          blue_data = rbbt.tsv(file='#{blue_data}')
          red_data = rbbt.tsv(file='#{red_data}')

          data.blue_me_points = data.frame(Dose=#{R.ruby2R [blue_dose_1, blue_dose_2]}, Response=#{R.ruby2R [blue_response_1, blue_response_2]})
          data.red_me_points = data.frame(Dose=#{R.ruby2R [red_dose_1, red_dose_2]}, Response=#{R.ruby2R [red_response_1, red_response_2]})

          blue.modelfile = #{R.ruby2R blue_modelfile}
          red.modelfile = #{R.ruby2R red_modelfile}
          least_squares = #{lss ? "TRUE" : "FALSE"}

          blue.invert = #{R.ruby2R blue_invert}
          red.invert = #{R.ruby2R red_invert}

          fix_ratio = #{R.ruby2R fix_ratio}

          more_doses = #{R.ruby2R more_doses.collect{|v| v.to_f}}
          more_responses = #{R.ruby2R more_responses.collect{|v| v.to_f}}
        
          blue.random.samples = #{R.ruby2R(blue_random_samples.flatten)}
          red.random.samples = #{R.ruby2R(red_random_samples.flatten)}

          blue.fit_dose = #{R.ruby2R fit_dose_d1}
          red.fit_dose = #{R.ruby2R fit_dose_d2}

          CI.plot_combination(blue_m, blue_dm, blue_dose, red_m, red_dm, red_dose, response,
            blue_data, red_data, data.blue_me_points, data.red_me_points, 
            blue.modelfile = blue.modelfile, red.modelfile=red.modelfile, least_squares=least_squares, blue.invert=blue.invert, red.invert=red.invert, 
            fix_ratio=fix_ratio, more_doses = more_doses, more_responses = more_responses, blue.random.samples = blue.random.samples, red.random.samples = red.random.samples, blue.fit_dose = blue.fit_dose, red.fit_dose = red.fit_dose)
        EOF

        R::SVG.ggplotSVG nil, plot_script, 5, 5, :R_method => :shell, :source => Rbbt.share.R["CI.R"].find
      end
    end
  end

  input :file, :tsv, "Dose response file", nil, :stream => true
  input :model_type, :select, "Model type for the DRC fit", "least_squares", :select_options => ["least_squares", "LL.2", "LL.3", "LL.4", "LL.5"]
  task :report => :tsv do |file,model_type|

    file = inputs[:file]
    file = TSV.open(file, :merge => true) unless TSV === file
    treatments = file.keys
    combinations = treatments.select{|t| t.include? '-'}
    drugs = treatments - combinations

    jobs = []
    combinations.each do |combination|
      blue_drug, red_drug = combination.split("-")

      blue_doses, blue_responses = file[blue_drug]
      red_doses, red_responses = file[red_drug]

      combination_doses, combination_responses = file[combination]
      Misc.zip_fields([combination_doses, combination_responses]).each do |doses,response|
        begin
        blue_dose, red_dose = doses.split("-")
        more_doses = combination_doses.collect{|p| p.split("-").inject(0){|acc,e| acc += e.to_f} }
        more_responses = combination_responses

        job_inputs = {
          :blue_doses => blue_doses.collect{|v| v.to_f},
          :blue_responses => blue_responses.collect{|v| v.to_f},
          :blue_dose => blue_dose.to_f,
          :red_doses => red_doses.collect{|v| v.to_f},
          :red_responses => red_responses.collect{|v| v.to_f},
          :red_dose => red_dose.to_f,
          :more_doses => more_doses,
          :more_responses => more_responses,
          :response => response.to_f,
          :model_type => model_type
        }

        job = CombinationIndex.job(:ci, [blue_drug, red_drug] * "-", job_inputs)
        jobs << job
        rescue Exception
          Log.exception $!
        end
      end
    end

    good_jobs = []

    Misc.bootstrap(jobs.shuffle, 10, :bar => self.progress_bar("Processing jobs")) do |job| 
      begin
        job.produce(false)
      rescue Exception
      end
    end

    jobs.each do |job|
      next unless job.done?
      good_jobs << job
    end

    good_jobs

    tsv = TSV.setup({}, :key_field => "Combination", :fields => ["Doses", "Response", "CI", "CI low", "CI high"], :type => :double)
    TSV.traverse good_jobs, :type => :array, :into => tsv do |dep|
      blue_drug, red_drug = dep.clean_name.split("-")
      blue_dose = dep.inputs[:blue_dose]
      red_dose = dep.inputs[:red_dose]
      response = dep.inputs[:response]
      ci = dep.info[:CI]
      random_CI = dep.info[:random_CI]
      doses = [blue_dose, red_dose] * "-"
      combination = [blue_drug, red_drug] * "-"
      [combination,[doses, response, ci, random_CI.min, random_CI.max]]
    end

    set_info :jobs, good_jobs.collect{|dep| dep.path }

    FileUtils.mkdir_p file('plots').find
    good_jobs.each do |dep|
      blue_dose, red_dose, response = dep.inputs.values_at :blue_dose, :red_dose, :response
      name = [dep.clean_name, blue_dose, red_dose, "%3f" % response] * "_"   + '.svg'
      FileUtils.cp dep.path, file('plots')[name].find
    end

    tsv.slice(tsv.fields - ["File"])
  end

end
