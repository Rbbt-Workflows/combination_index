
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
    blue_doses.zip(blue_responses).each{|d,e| blue_dose_responses[d] ||= []; blue_dose_responses[d] << e}
    blue_mean_dose_responses = {}
    blue_dose_responses.each do |dose,responses|
      blue_mean_dose_responses[dose] = Misc.mean responses
    end

    red_dose_responses = {}
    red_doses.zip(red_responses).each{|d,e| red_dose_responses[d] ||= []; red_dose_responses[d] << e}
    red_mean_dose_responses = {}
    red_dose_responses.each do |dose,responses|
      red_mean_dose_responses[dose] = Misc.mean responses
    end

    combination_ratio = blue_dose.to_f / red_dose.to_f
    additive_predictions = {}
    blue_doses.each do |bd|
      rd = red_doses.sort_by{|d| (bd.to_f - combination_ratio * d.to_f).abs}.first
      cd = bd + rd
      pa = if response_type.to_s == "viability"
             1 - CombinationIndex.predicted_bliss(1 - blue_mean_dose_responses[bd], 1 - red_mean_dose_responses[rd])
           else
             CombinationIndex.predicted_bliss(blue_mean_dose_responses[bd], red_mean_dose_responses[rd])
           end
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

    #{{{ P-value
    
    additive_prediction_all = {}
    blue_doses.each do |bd|
      rd = red_doses.sort_by{|d| (bd.to_f - combination_ratio * d.to_f).abs}.first
      cd = bd + rd
      blue_dose_responses[bd].each do |br|
        red_dose_responses[rd].each do |rr|
          pa = if response_type.to_s == "viability"
                 1 - CombinationIndex.predicted_bliss(1 - br, 1 - rr)
               else
                 CombinationIndex.predicted_bliss(br, rr)
               end
          additive_prediction_all[cd] ||= []
          additive_prediction_all[cd] << pa
        end
      end
    end

    relevant_responses = more_doses.zip(more_responses).select{|d,r| (d.to_f - blue_dose - red_dose).abs < 0.0001 }.collect{|d,r| r.to_f }
    additive_reponses = additive_prediction_all[blue_dose + red_dose]

    pvalue = R.run(<<-EOF).read.split("\n").last.to_f
relevant_responses = #{R.ruby2R relevant_responses}
additive_reponses = #{R.ruby2R additive_reponses}
p.value = t.test(relevant_responses, additive_reponses)$p.value
cat(p.value)
    EOF

    set_info :bliss_pvalue, pvalue

    #{{{ MAKE BLISS PLOT
    blue_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    blue_doses.zip(blue_responses).each do |dose, response|
      blue_tsv[Misc.obj2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    red_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    red_doses.zip(red_responses).each do |dose, response|
      red_tsv[Misc.obj2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    bliss_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    additive_predictions.each do |dose, response|
      bliss_tsv[Misc.obj2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    bliss_tsv_all = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    additive_prediction_all.each do |adose, aresponses|
      aresponses.each do |aresponse|
        bliss_tsv_all[Misc.obj2md5(:values => [adose,aresponse] * ":")] =  [adose, aresponse]
      end
    end


    log :CI_plot, "Drawing Bliss plot"
    svg = TmpFile.with_file(blue_tsv.to_s) do |blue_data|
      TmpFile.with_file(red_tsv.to_s) do |red_data|
      TmpFile.with_file(bliss_tsv.to_s) do |bliss_data|
      TmpFile.with_file(bliss_tsv_all.to_s) do |bliss_data_all|

        plot_script =<<-EOF
          blue_dose = #{R.ruby2R blue_dose}
          red_dose = #{R.ruby2R red_dose}
          response = #{R.ruby2R response}

          blue_data = rbbt.tsv(file='#{blue_data}')
          red_data = rbbt.tsv(file='#{red_data}')
          bliss_data = rbbt.tsv(file='#{bliss_data}')
          all_bliss_data = rbbt.tsv(file='#{bliss_data_all}')

          fix_ratio = #{R.ruby2R fix_ratio}

          more_doses = #{R.ruby2R more_doses.collect{|v| v.to_f}}
          more_responses = #{R.ruby2R more_responses.collect{|v| v.to_f}}
        
          CI.plot_combination.bliss(blue_dose, red_dose, response,
            blue_data, red_data, bliss_data,
            fix_ratio=fix_ratio, more_doses = more_doses, more_responses = more_responses, all_bliss_data=all_bliss_data)
        EOF

        R::SVG.ggplotSVG nil, plot_script, 5, 5, :R_method => :shell, :source => Rbbt.share.R["CI.R"].find, :debug => true
      end
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
      next if blue_doses.nil? || red_doses.nil?

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

    Open.mkdir file('plots').find
    good_jobs.each do |dep|
      blue_dose, red_dose, response = dep.inputs.values_at :blue_dose, :red_dose, :response
      name = [dep.clean_name, blue_dose, red_dose, "%3f" % response] * "_"   + '.svg'
      Open.cp dep.path, file('plots')[name].find
    end

    tsv.slice(tsv.fields - ["File"])
  end
end
