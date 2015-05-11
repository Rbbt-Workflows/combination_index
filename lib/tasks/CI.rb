require 'rbbt/util/R/svg'

module CombinationIndex
 
  input :doses, :array, "Doses"
  input :effects, :array, "Effects 0 to 1"
  input :median_point, :float, "If fitted, point around which predictions are made", 0.5
  input :model_type, :select, "Model type for the DRC fit", ":LL.5()", :select_options => [":least_squares", ":LL.2()", ":LL.3()", ":LL.4()", ":LL.5()"]
  extension :svg
  task :fit => :text do |doses,effects,median_point,model_type|
    doses = doses.collect{|v| v.to_f}
    effects = effects.collect{|v| v.to_f}
    median_point = median_point.to_f

    tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Effect"], :type => :single)
    doses.zip(effects).each do |dose, effect|
      tsv[Misc.hash2md5(:values => [dose,effect] * ":")] = [dose, effect]
    end

    lss = model_type =~ /least_squares/
    log = true if lss
    invert = false
    begin
      FileUtils.mkdir_p files_dir
      modelfile = file(:model)
      if invert
        m, dm, dose1, effect1, dose2, effect2, *random_samples = CombinationIndex.fit_m_dm(doses, effects.collect{|e| 1.0 - e}, modelfile, 1.0 - median_point, model_type)
        m = - m if m
        random_samples = random_samples.collect{|_m,_dm| [-_m, _dm] }
        effect1 = 1.0 - effect1
        effect2 = 1.0 - effect2
      else
        m, dm, dose1, effect1, dose2, effect2, *random_samples  = CombinationIndex.fit_m_dm(doses, effects, modelfile, median_point, model_type)
        raise "Error computing m and dm" if m.to_s == "NaN"
      end

      modelfile = nil unless modelfile.exists?

      plot_script =<<-EOF
        m = #{R.ruby2R m}
        dm = #{R.ruby2R dm}
        data.me_points = data.frame(Dose=#{R.ruby2R [dose1, dose2]}, Effect=#{R.ruby2R [effect1, effect2]})
        least_squares = #{lss ? 'TRUE' : 'FALSE'}
        invert = #{invert ? 'TRUE' : 'FALSE'}
        modelfile = #{R.ruby2R modelfile}
        random_samples = #{R.ruby2R random_samples.flatten}

        CI.plot_fit(m,dm,data,data.me_points, modelfile, least_squares, invert, random_samples)
      EOF

      R::SVG.ggplotSVG tsv, plot_script, 5, 5, :R_method => :shell, :source => Rbbt.share.R["CI.R"].find(:lib)
    rescue Exception
      Log.exception $!
      if invert
        raise $!
      else
        Log.warn "Invert and repeat"
        invert = true
        retry
      end
    ensure
      {:random_samples => random_samples, :m => m, :dm => dm, :dose1 => dose1, :dose2 => dose2, :effect1 => effect1, :effect2 => effect2, :invert => invert}.each do |k,v|
        set_info k, v
      end
    end
  end

  input :blue_doses, :array, "Blue doses"
  input :blue_effects, :array, "Blue doses"
  input :red_doses, :array, "Red doses"
  input :red_effects, :array, "Red doses"
  input :blue_dose, :float, "Blue combination dose"
  input :red_dose, :float, "Blue combination dose"
  input :effect, :float, "Combination effect"
  input :fix_ratio, :boolean, "Fix combination ratio dose", false
  input :model_type, :select, "Model type for the DRC fit", ":LL.5()", :select_options => [":least_squares", ":LL.2()", ":LL.3()", ":LL.4()", ":LL.5()"]
  input :more_doses, :array, "More combination dose"
  input :more_effects, :array, "More combination effects"
  extension :svg
  dep do |jobname, options|
    model_type = options[:model_type]

    if model_type.to_s =~ /least_squares/
      median_point = 0.5
    else
      median_point = options[:effect].to_f
    end

    [
      CombinationIndex.job(:fit, nil, :doses => options[:blue_doses], :effects => options[:blue_effects], :median_point => median_point, :model_type => model_type),
      CombinationIndex.job(:fit, nil, :doses => options[:red_doses], :effects => options[:red_effects], :median_point => median_point, :model_type => model_type)
    ]
  end
  task :ci => :text do |blue_doses,blue_effects,red_doses,red_effects,blue_dose,red_dose,effect,fix_ratio,model_type,more_doses,more_effects|
    blue_step, red_step = dependencies
    blue_doses = blue_doses.collect{|v| v.to_f}
    blue_effects = blue_effects.collect{|v| v.to_f}
    red_doses = red_doses.collect{|v| v.to_f}
    red_effects = red_effects.collect{|v| v.to_f}
    blue_random_samples = blue_step.info[:random_samples] || []
    red_random_samples = red_step.info[:random_samples] || []

    blue_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Effect"], :type => :single)
    blue_doses.zip(blue_effects).each do |dose, effect|
      blue_tsv[Misc.hash2md5(:values => [dose,effect] * ":")] = [dose, effect]
    end

    red_tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Effect"], :type => :single)
    red_doses.zip(red_effects).each do |dose, effect|
      red_tsv[Misc.hash2md5(:values => [dose,effect] * ":")] = [dose, effect]
    end

    blue_m, blue_dm, blue_dose_1, blue_effect_1, blue_dose_2, blue_effect_2, blue_invert  = blue_step.info.values_at :m, :dm, :dose1, :effect1, :dose2, :effect2, :invert
    blue_modelfile = blue_step.file(:model)
    blue_modelfile = nil unless blue_modelfile.exists?

    red_m, red_dm, red_dose_1, red_effect_1, red_dose_2, red_effect_2, red_invert  = red_step.info.values_at :m, :dm, :dose1, :effect1, :dose2, :effect2, :invert
    red_modelfile = red_step.file(:model)
    red_modelfile = nil unless red_modelfile.exists?

    lss = true if model_type =~ /least_squares/

    if Float === blue_dm and Float === red_dm
      ci = CombinationIndex.ci_value(blue_dose, blue_dm, blue_m, red_dose, red_dm, red_m, effect)
      random_doses = []
      random_ci = []

      blue_random_samples.zip(red_random_samples).collect do |bi,ri|
        rblue_m, rblue_dm = bi
        rred_m, rred_dm = ri
        rci = CombinationIndex.ci_value(blue_dose, rblue_dm, rblue_m, red_dose, rred_dm, rred_m, effect)
        random_ci << rci
      end

      set_info :CI, ci
      set_info :random_CI, random_ci.sort
      set_info :GI50, CombinationIndex.additive_dose(0.5, blue_dose, red_dose, blue_m, blue_dm, red_m, red_dm)

      matching_effects = []
      more_doses.each_with_index{|dose,i|
        if (dose.to_f - (red_dose.to_f + blue_dose.to_f)).abs < 0.0001
          matching_effects << more_effects[i]
        end
      }

      if matching_effects.length > 2
        matching_CI = matching_effects.collect{|_effect|
        }
      end
    else
      set_info :CI, nil
    end

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

          effect = #{R.ruby2R effect}

          blue_data = rbbt.tsv(file='#{blue_data}')
          red_data = rbbt.tsv(file='#{red_data}')

          data.blue_me_points = data.frame(Dose=#{R.ruby2R [blue_dose_1, blue_dose_2]}, Effect=#{R.ruby2R [blue_effect_1, blue_effect_2]})
          data.red_me_points = data.frame(Dose=#{R.ruby2R [red_dose_1, red_dose_2]}, Effect=#{R.ruby2R [red_effect_1, red_effect_2]})

          blue.modelfile = #{R.ruby2R blue_modelfile}
          red.modelfile = #{R.ruby2R red_modelfile}
          least_squares = #{lss ? "TRUE" : "FALSE"}

          blue.invert = #{R.ruby2R blue_invert}
          red.invert = #{R.ruby2R red_invert}

          fix_ratio = #{R.ruby2R fix_ratio}

          more_doses = #{R.ruby2R more_doses.collect{|v| v.to_f}}
          more_effects = #{R.ruby2R more_effects.collect{|v| v.to_f}}
        
          blue.random.samples = #{R.ruby2R(blue_random_samples.flatten)}
          red.random.samples = #{R.ruby2R(red_random_samples.flatten)}

          CI.plot_combination(blue_m, blue_dm, blue_dose, red_m, red_dm, red_dose, effect,
            blue_data, red_data, data.blue_me_points, data.red_me_points, 
            blue.modelfile = blue.modelfile, red.modelfile=red.modelfile, least_squares=least_squares, blue.invert=blue.invert, red.invert=red.invert, 
            fix_ratio=fix_ratio, more_doses = more_doses, more_effects = more_effects, blue.random.samples = blue.random.samples, red.random.samples = red.random.samples)
        EOF

        R::SVG.ggplotSVG nil, plot_script, 5, 5, :R_method => :shell, :source => Rbbt.share.R["CI.R"].find
      end
    end
  end

  export_asynchronous :fit, :ci
end
