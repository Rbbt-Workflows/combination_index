
module CombinationIndex
  input :doses, :array, "Doses"
  input :responses, :array, "Responses 0 to 1"
  input :median_point, :float, "If fitted, point around which predictions are made", 0.5
  input :model_type, :select, "Model type for the DRC fit", "least_squares", :select_options => ["least_squares", "LL.2", "LL.3", "LL.4", "LL.5"]
  extension :svg
  task :fit => :text do |doses,responses,median_point,model_type|
    doses = doses.collect{|v| v.to_f}
    responses = responses.collect{|v| v.to_f}
    median_point = median_point.to_f

    tsv = TSV.setup({}, :key_field => "Measurement", :fields => ["Dose", "Response"], :type => :single)
    doses.zip(responses).each do |dose, response|
      tsv[Misc.hash2md5(:values => [dose,response] * ":")] = [dose, response]
    end

    lss = model_type =~ /least_squares/
    log = true if lss
    invert = false
    begin
      FileUtils.mkdir_p files_dir
      modelfile = file(:model)
      if invert
        m, dm, dose1, response1, dose2, response2, gi50, *random_samples = 
          CombinationIndex.fit_m_dm(doses, responses.collect{|e| 1.0 - e}, modelfile, 1.0 - median_point, model_type)
        m = - m if m

        raise "Error computing fit" if response1.nil? or response2.nil?

        random_samples = random_samples.collect{|_m,_dm| [-_m, _dm] }
        response1 = 1.0 - response1
        response2 = 1.0 - response2
      else
        m, dm, dose1, response1, dose2, response2, gi50, *random_samples  = 
          CombinationIndex.fit_m_dm(doses, responses, modelfile, median_point, model_type)
        raise RbbtException, "Error computing m and dm" if m.to_s == "NaN"
      end

      set_info 'GI50', gi50

      modelfile = nil unless modelfile.exists?

      plot_script =<<-EOF
        m = #{R.ruby2R m}
        dm = #{R.ruby2R dm}
        data.me_points = data.frame(Dose=#{R.ruby2R [dose1, dose2]}, Response=#{R.ruby2R [response1, response2]})
        least_squares = #{lss ? 'TRUE' : 'FALSE'}
        invert = #{invert ? 'TRUE' : 'FALSE'}
        modelfile = #{R.ruby2R modelfile}
        random_samples = #{R.ruby2R random_samples.flatten}

        CI.plot_fit(m,dm,data,data.me_points, modelfile, least_squares, invert, random_samples)
      EOF

      log(:plot, invert ? "Drawing plot (inverted)" : "Drawing plot") do
        R::SVG.ggplotSVG tsv, plot_script, 5, 5, :R_method => :shell, :source => Rbbt.share.R["CI.R"].find(:lib)
      end
    rescue Exception
      Log.warn $!.message
      if invert
        raise RbbtException, "Could not draw fit"
      else
        Log.warn "Invert and repeat"
        invert = true
        retry
      end
    ensure
      log(:saving_info, "Saving information") 
      merge_info({:random_samples => random_samples, :m => m, :dm => dm, :dose1 => dose1, :dose2 => dose2, :response1 => response1, :response2 => response2, :invert => invert})
    end
  end

end
