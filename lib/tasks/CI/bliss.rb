
module CombinationIndex
  input :blue_doses, :array, "Blue doses"
  input :blue_responses, :array, "Blue doses"
  input :red_doses, :array, "Red doses"
  input :red_responses, :array, "Red doses"
  input :blue_dose, :float, "Blue combination dose"
  input :red_dose, :float, "Blue combination dose"
  input :response, :float, "Combination response"
  input :fix_ratio, :boolean, "Fix combination ratio dose", false
  input :more_doses, :array, "More combination dose"
  input :more_responses, :array, "More combination responses"
  input :response_type, :select, "Type of response: viability or effect", :viability, :select_options => [:viability, :effect]
  extension :svg
  task :bliss => :text do |blue_doses,blue_responses,red_doses,red_responses,blue_dose,red_dose,response,fix_ratio,more_doses,more_responses, response_type|

    #{{{ CALCULATE BLISS
    blue_doses = blue_doses.collect{|v| v.to_f}
    blue_responses = blue_responses.collect{|v| v.to_f}
    red_doses = red_doses.collect{|v| v.to_f}
    red_responses = red_responses.collect{|v| v.to_f}

    blue_dose_responses = {}
    blue_doses.zip(blue_responses).each{|d,e| blue_dose_responses[d] = blue_dose_responses[d] || []; blue_dose_responses[d] << e}
    blue_mean_dose_responses = {}
    blue_dose_responses.each do |dose,responses|
      blue_mean_dose_responses[dose] = Misc.mean responses
    end

    red_dose_responses = {}
    red_doses.zip(red_responses).each{|d,e| red_dose_responses[d] = red_dose_responses[d] || []; red_dose_responses[d] << e}
    red_mean_dose_responses = {}
    red_dose_responses.each do |dose,responses|
      red_mean_dose_responses[dose] = Misc.mean responses
    end

    combination_ratio = blue_dose.to_f / red_dose.to_f
    additive_predictions = {}
    blue_doses.each do |bd|
      rd = red_doses.sort_by{|d| (bd.to_f - combination_ratio * d.to_f).abs}.first
      pa = if response_type.to_s == "viability"
             1 - CombinationIndex.predicted_bliss(1 - blue_mean_dose_responses[bd], 1 - red_mean_dose_responses[rd])
           else
             CombinationIndex.predicted_bliss(blue_mean_dose_responses[bd], red_mean_dose_responses[rd])
           end
      cd = bd + rd
      additive_predictions[cd] = pa
    end

    if response_type.to_s == "viability"
      predicted_additive = 1 - CombinationIndex.predicted_bliss(1 - blue_mean_dose_responses[blue_dose], 1 - red_mean_dose_responses[red_dose])
    else
      predicted_additive = CombinationIndex.predicted_bliss(blue_mean_dose_responses[blue_dose], red_mean_dose_responses[red_dose])
    end
    excess = response - predicted_additive 

    set_info :bliss_excess, excess
    set_info :bliss_prediction, predicted_additive

    #{{{ MAKE BLISS PLOT
    blue_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    blue_doses.zip(blue_responses).each do |dose, response|
      blue_tsv[Misc.hash2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    red_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    red_doses.zip(red_responses).each do |dose, response|
      red_tsv[Misc.hash2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    bliss_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    additive_predictions.each do |dose, response|
      bliss_tsv[Misc.hash2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    #blue_m, blue_dm, blue_dose_1, blue_response_1, blue_dose_2, blue_response_2, blue_invert  = blue_step.info.values_at :m, :dm, :dose1, :response1, :dose2, :response2, :invert
    #blue_modelfile = blue_step.file(:model)
    #blue_modelfile = nil unless blue_modelfile.exists?

    #red_m, red_dm, red_dose_1, red_response_1, red_dose_2, red_response_2, red_invert  = red_step.info.values_at :m, :dm, :dose1, :response1, :dose2, :response2, :invert
    #red_modelfile = red_step.file(:model)
    #red_modelfile = nil unless red_modelfile.exists?



    log :CI_plot, "Drawing Bliss plot"
    svg = TmpFile.with_file(nil, false) do |blue_data|
      Open.write(blue_data, blue_tsv.to_s)
      TmpFile.with_file(nil, false) do |red_data|
        Open.write(red_data, red_tsv.to_s)
      TmpFile.with_file(nil, false) do |bliss_data|
        Open.write(bliss_data, bliss_tsv.to_s)


        plot_script =<<-EOF
          #blue_m = {R.ruby2R blue_m}
          #blue_dm = {R.ruby2R blue_dm}
          blue_dose = #{R.ruby2R blue_dose}

          #red_m = {R.ruby2R red_m}
          #red_dm = {R.ruby2R red_dm}
          red_dose = #{R.ruby2R red_dose}

          response = #{R.ruby2R response}

          blue_data = rbbt.tsv(file='#{blue_data}')
          red_data = rbbt.tsv(file='#{red_data}')
          bliss_data = rbbt.tsv(file='#{bliss_data}')

          #data.blue_me_points = data.frame(Dose={R.ruby2R [blue_dose_1, blue_dose_2]}, Response={R.ruby2R [blue_response_1, blue_response_2]})
          #data.red_me_points = data.frame(Dose={R.ruby2R [red_dose_1, red_dose_2]}, Response={R.ruby2R [red_response_1, red_response_2]})

          #blue.modelfile = {R.ruby2R blue_modelfile}
          #red.modelfile = {R.ruby2R red_modelfile}
          #least_squares = {lss ? "TRUE" : "FALSE"}

          #blue.invert = {R.ruby2R blue_invert}
          #red.invert = {R.ruby2R red_invert}

          fix_ratio = #{R.ruby2R fix_ratio}

          more_doses = #{R.ruby2R more_doses.collect{|v| v.to_f}}
          more_responses = #{R.ruby2R more_responses.collect{|v| v.to_f}}
        
          #blue.random.samples = {R.ruby2R(blue_random_samples.flatten)}
          #red.random.samples = {R.ruby2R(red_random_samples.flatten)}

          #blue.fit_dose = {R.ruby2R fit_dose_d1}
          #red.fit_dose = {R.ruby2R fit_dose_d2}

          #CI.plot_combination.bliss(blue_m, blue_dm, blue_dose, red_m, red_dm, red_dose, response,
          #  blue_data, red_data, data.blue_me_points, data.red_me_points, 
          #  blue.modelfile = blue.modelfile, red.modelfile=red.modelfile, least_squares=least_squares, blue.invert=blue.invert, red.invert=red.invert, 
          #  fix_ratio=fix_ratio, more_doses = more_doses, more_responses = more_responses, blue.random.samples = blue.random.samples, red.random.samples = red.random.samples, blue.fit_dose = blue.fit_dose, red.fit_dose = red.fit_dose)
          
          CI.plot_combination.bliss(blue_dose, red_dose, response,
            blue_data, red_data, bliss_data,
            fix_ratio=fix_ratio, more_doses = more_doses, more_responses = more_responses)
        EOF

        R::SVG.ggplotSVG nil, plot_script, 5, 5, :R_method => :shell, :source => Rbbt.share.R["CI.R"].find, :debug => true
      end
    end
    end
  end

 
  input :file, :tsv, "Dose response file", nil, :stream => true
  input :fix_ratio, :boolean, "Fix combination ratio dose", false
  task :report_bliss => :tsv do |file,fix_ratio|

    file = TSV.open(file, :merge => true) unless TSV === file
    treatments = file.keys
    combinations = treatments.select{|t| t.include? '-'}
    drugs = treatments - combinations

    jobs = []
    combinations.each do |combination|
      blue_drug, red_drug = combination.split(CombinationIndex::COMBINATION_SEP)

      blue_doses, blue_responses = file[blue_drug]
      red_doses, red_responses = file[red_drug]

      combination_doses, combination_responses = file[combination]
      Misc.zip_fields([combination_doses, combination_responses]).each do |doses,response|
        begin
        blue_dose, red_dose = doses.split(CombinationIndex::COMBINATION_SEP)
        ratio = blue_dose.to_f / red_dose.to_f
        good_doses = combination_doses.collect{|p| r,b = p.split(CombinationIndex::COMBINATION_SEP); Misc.in_delta?(r.to_f / b.to_f, ratio) }
        more_doses = Misc.choose(combination_doses, good_doses).collect{|p| p.split(CombinationIndex::COMBINATION_SEP).inject(0){|acc,e| acc += e.to_f} }
        more_responses = Misc.choose(combination_responses, good_doses)

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
          :fix_ratio => fix_ratio,
        }

        job = CombinationIndex.job(:bliss, [blue_drug, red_drug] * "-", job_inputs)
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

    tsv = TSV.setup({}, :key_field => "Combination", :fields => ["Doses", "Response", "Bliss excess"], :type => :double)
    TSV.traverse good_jobs, :type => :array, :into => tsv do |dep|
      blue_drug, red_drug = dep.clean_name.split(CombinationIndex::COMBINATION_SEP)
      blue_dose = dep.inputs[:blue_dose]
      red_dose = dep.inputs[:red_dose]
      response = dep.inputs[:response]
      bliss = dep.info[:bliss_excess]
      doses = [blue_dose, red_dose] * "-"
      combination = [blue_drug, red_drug] * "-"
      [combination,[doses, response, bliss]]
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
