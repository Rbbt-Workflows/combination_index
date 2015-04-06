require 'rbbt/util/R/svg'

module CombinationIndex
 
  input :doses, :array, "Doses"
  input :effects, :array, "Effects 0 to 1"
  input :median_point, :float, "If fitted, point around which predictions are made", 0.5
  input :model_type, :select, "Model type for the DRC fit", ":LL.5()", :select_options => [":LL.2()", ":LL.3()", ":LL.4()", ":LL.5()"]
  extension :svg
  task :fit => :text do |doses,effects,median_point,model_type|
    doses = doses.collect{|v| v.to_f}
    effects = effects.collect{|v| v.to_f}
    median_point = median_point.to_f

    tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Effect"], :type => :single)
    doses.zip(effects).each do |dose, effect|
      tsv[Misc.hash2md5(:values => [dose,effect] * ":")] = [dose, effect]
    end

    invert = false
    begin
      FileUtils.mkdir_p files_dir
      modelfile = file(:model)
      if invert
        m, dm, dose1, effect1, dose2, effect2  = CombinationIndex.fit_m_dm(doses, effects.collect{|e| 1.0 - e}, modelfile, 1.0 - median_point, model_type)
        m = - m if m
        effect1 = 1.0 - effect1
        effect2 = 1.0 - effect2
      else
        m, dm, dose1, effect1, dose2, effect2  = CombinationIndex.fit_m_dm(doses, effects, modelfile, median_point, model_type)
        raise "Error computing m and dm" if m.to_s == "NaN"
      end

      plot_script =<<-EOF
        source('#{Rbbt.share.R["CI.R"].find(:lib)}')
        m = #{R.ruby2R m}
        dm = #{R.ruby2R dm}

        data.me = CI.me_curve(m, dm)
        max = max(data$Dose)
        min = min(data$Dose)
        data.me = subset(data.me, data.me$Effect <= 1)
        data.me = subset(data.me, data.me$Dose <= max)
        data.me = subset(data.me, data.me$Dose >= min)

        data.me_points = data.frame(Dose=#{R.ruby2R [dose1, dose2]}, Effect=#{R.ruby2R [effect1, effect2]})

        data.drc = data.frame(Dose=data.me$Dose*1.01);

        #{ "model = rbbt.model.load('#{modelfile}'); data.drc$Effect = predict(model, data.drc);" if File.exists? modelfile}
        #{ "data.drc$Effect = data.me$Effect" unless File.exists? modelfile}

        #{(invert and File.exists?(modelfile)) ? 'data.drc$Effect = 1 - data.drc$Effect' : ''}

        ggplot(aes(x=Dose, y=Effect), data=data) +
          scale_x_log10() + annotation_logticks() +
          geom_line(data=data.me, col='blue', cex=2) +
          geom_line(data=data.drc, col='blue', linetype='dashed',cex=2) +
          geom_point(cex=5) + 
          ylim(c(0,1)) +
          geom_point(data=data.me_points, col='blue',cex=5) 
      EOF

      R::SVG.ggplotSVG tsv, plot_script, 5, 5, :R_method => :shell
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
      {:m => m, :dm => dm, :dose1 => dose1, :dose2 => dose2, :effect1 => effect1, :effect2 => effect2, :invert => invert}.each do |k,v|
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
  input :model_type, :select, "Model type for the DRC fit", ":LL.5()", :select_options => [":LL.2()", ":LL.3()", ":LL.4()", ":LL.5()"]
  input :more_doses, :array, "More combination dose"
  input :more_effects, :array, "More combination effects"
  extension :svg
  dep do |jobname, options|
    median_point = options[:effect].to_f
    model_type = options[:model_type]
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

    red_m, red_dm, red_dose_1, red_effect_1, red_dose_2, red_effect_2, red_invert  = red_step.info.values_at :m, :dm, :dose1, :effect1, :dose2, :effect2, :invert
    red_modelfile = red_step.file(:model)

    if Float === blue_dm and Float === red_dm
      set_info :CI, CombinationIndex.ci_value(blue_dose, blue_dm, blue_m, red_dose, red_dm, red_m, effect)
    else
      set_info :CI, nil
    end

    svg = TmpFile.with_file do |blue_data|
      Open.write(blue_data, blue_tsv.to_s)
      TmpFile.with_file do |red_data|
        Open.write(red_data, red_tsv.to_s)

        plot_script =<<-EOF
          source('#{Rbbt.share.R["CI.R"].find}')

          blue_data = rbbt.tsv(file='#{blue_data}')
          red_data = rbbt.tsv(file='#{red_data}')

          blue_m = #{R.ruby2R blue_m}
          blue_dm = #{R.ruby2R blue_dm}

          red_m = #{R.ruby2R red_m}
          red_dm = #{R.ruby2R red_dm}

          data.blue_me = CI.me_curve(blue_m, blue_dm)
          data.blue_me_points = data.frame(Dose=#{R.ruby2R [blue_dose_1, blue_dose_2]}, Effect=#{R.ruby2R [blue_effect_1, blue_effect_2]})

          data.red_me = CI.me_curve(red_m, red_dm)
          data.red_me_points = data.frame(Dose=#{R.ruby2R [red_dose_1, red_dose_2]}, Effect=#{R.ruby2R [red_effect_1, red_effect_2]})

          max = max(c(blue_data$Dose, red_data$Dose))
          min = min(c(blue_data$Dose, red_data$Dose))

          data.blue_me = subset(data.blue_me, data.blue_me$Effect <= 1)
          data.blue_me = subset(data.blue_me, data.blue_me$Dose <= max)
          data.blue_me = subset(data.blue_me, data.blue_me$Dose >= min)

          data.red_me = subset(data.red_me, data.red_me$Effect <= 1)
          data.red_me = subset(data.red_me, data.red_me$Dose <= max)
          data.red_me = subset(data.red_me, data.red_me$Dose >= min)


          blue_model = rbbt.model.load('#{blue_modelfile}');
          data.blue_drc = data.frame(Dose=data.blue_me$Dose);
          data.blue_drc$Effect = predict(blue_model, data.blue_drc);
          #{"data.blue_drc$Effect = 1 - data.blue_drc$Effect" if blue_invert}

          data.add = CI.add_curve(blue_m, red_m, blue_dm, red_dm, #{blue_dose}, #{red_dose})

          data.add = subset(data.add, data.add$Effect <= 1)
          data.add = subset(data.add, data.add$Dose <= max)
          data.add = subset(data.add, data.add$Dose >= min)


          red_model = rbbt.model.load('#{red_modelfile}');
          data.red_drc = data.frame(Dose=data.red_me$Dose);
          data.red_drc$Effect = predict(red_model, data.red_drc);
          #{"data.red_drc$Effect = 1 - data.red_drc$Effect" if red_invert}

          blue_ratio = #{blue_dose + red_dose}/#{blue_dose}
          red_ratio = #{blue_dose + red_dose}/#{red_dose}

          #{ "blue_ratio = 1; red_ratio = 1" unless fix_ratio }

          blue_data$Dose = blue_data$Dose * blue_ratio
          data.blue_me$Dose = data.blue_me$Dose * blue_ratio
          data.blue_drc$Dose = data.blue_drc$Dose * blue_ratio
          data.blue_me_points$Dose = data.blue_me_points$Dose * blue_ratio

          red_data$Dose = red_data$Dose * red_ratio
          data.red_me$Dose = data.red_me$Dose * red_ratio
          data.red_drc$Dose = data.red_drc$Dose * red_ratio
          data.red_me_points$Dose = data.red_me_points$Dose * red_ratio

          ggplot(aes(x=as.numeric(Dose), y=as.numeric(Effect)), data=blue_data) + 
            scale_x_log10() + annotation_logticks() +
            xlab("Combination dose") +
            ylab("Effect") +
            geom_point(data=blue_data, col='blue') +
            geom_point(data=red_data, col='red') +

            geom_line(data=data.blue_me, col='blue', cex=2) +
            geom_line(data=data.red_me, col='red', cex=2) +

            geom_line(data=data.blue_drc, linetype='dashed', col='blue', cex=1) +
            geom_line(data=data.red_drc, linetype='dashed', col='red', cex=1) +

            geom_line(data=data.add, col='black', cex=2) +

            geom_point(x=log10(#{blue_dose + red_dose}), y=#{effect}, col='black',cex=5) +

            #{(more_doses and more_doses.any?) ? (more_doses.zip(more_effects).collect{|d,e|"geom_point(x=log10(#{d.to_f}), y=#{e.to_f},col='black',cex=3) +" } * "\n" + "\n") : ''}
          
            geom_point(data=data.blue_me_points, col='blue',cex=5)  +
            geom_point(data=data.red_me_points, col='red',cex=5) 
        EOF

        R::SVG.ggplotSVG nil, plot_script, 5, 5, :R_method => :shell
      end
    end
  end

  export_asynchronous :fit, :ci
end
