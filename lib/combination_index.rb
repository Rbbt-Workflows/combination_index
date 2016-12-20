require 'rbbt/util/R/model'

Log._ignore_stderr do
  R.eval_a 'library(drc)'
end
module CombinationIndex

  def self.response_ratio(response, max = 1.0)
    response / (max.to_f - response)
  end

  def self.additive_dose(level, blue_dose, red_dose, blue_m, blue_dm, red_m, red_dm)
    ratio = self.response_ratio(level); 
    t1 =  blue_dose/(blue_dm*(ratio**(1/blue_m)))
    t2 =  red_dose/(red_dm*(ratio**(1/red_m)))
    (blue_dose+red_dose)/(t1 + t2)
  end

  def self.m_dm(dose_1, response_1, dose_2, response_2, max_response = 1)
    max_response = 1

    e_ratio1 = self.response_ratio response_1, max_response
    e_ratio2 = self.response_ratio response_2, max_response

    le1 = Math.log(e_ratio1)
    le2 = Math.log(e_ratio2)

    ld1 = Math.log(dose_1)
    ld2 = Math.log(dose_2)

    m = ( le1 - le2 ) / (ld1 - ld2)
    dm = dose_1/ ((e_ratio1) ** (1/m))

    raise "Negative median drug dose level" if dm <= 0

    [m, dm]
  end

  def self.sample_m_dm(dose_1, response1_info, dose_2, response2_info, max_response)
    fit1 = response1_info["fit"]
    fit2 = response2_info["fit"]

    sd1 = (response1_info["upper"] - response1_info["fit"])/1.96
    sd2 = (response2_info["upper"] - response2_info["fit"])/1.96
    size = 25
    diffs1 = nil
    diffs2 = nil
    diffs1 = R.eval_a "rnorm(#{R.ruby2R size*4},0,#{R.ruby2R sd1})"
    diffs2 = R.eval_a "rnorm(#{R.ruby2R size*4},0,#{R.ruby2R sd2})"

    found = 0
    diffs1.zip(diffs2).collect{|diff1, diff2|
      next nil if found == size
      begin
        e1 = fit1 + diff1
        e1 = 0.99 if e1 > 0.99
        e1 = 0.01 if e1 < 0.01

        e2 = fit2 + diff2
        e2 = 0.99 if e2 > 0.99
        e2 = 0.01 if e2 < 0.01

        m, dm = self.m_dm(dose_1, e1, dose_2, fit2 + diff2)
        m_to_s = m.to_s
        dm_to_s = dm.to_s
        raise "NaN found" if m_to_s == "NaN" or dm_to_s == "NaN" 
        raise "Infinity found" if m_to_s == "Infinity" or dm_to_s == "Infinity" 
        found += 1
        [m, dm]
      rescue
        nil
      end
    }.compact
  end

  def self.adjust_dose(model, response, min_dose, max_dose, inverse=false)
    dose = min_dose + (max_dose - min_dose)/2

    real_max_dose = max_dose
    real_min_dose = min_dose

    new_response = model.predict(dose)
    delta = new_response - response
    while delta.abs > 0.01 and real_max_dose - dose > real_max_dose / 100 and dose - real_min_dose > real_min_dose / 100
      if (delta < 0 and not inverse) or (delta > 0 and inverse)
        min_dose = dose
        dose = dose + (max_dose - dose) / 2
      else
        max_dose = dose
        dose = dose - (dose - min_dose) / 2
      end
      new_response = model.predict(dose)
      delta = new_response - response
    end
    dose
  end

  def self.separate_doses(dose1, dose2, min_dose, max_dose)
    if (dose2 - dose1).abs < dose2/Math.log(dose2)
      dose1 = min_dose + (dose1 - min_dose)/10
      dose2 += (max_dose - dose2)/10
      dose2 = max_dose if dose2 > max_dose
    end

    [dose1, dose2]
  end

  def self.fit_m_dm(doses, responses, model_file = nil, median_point = 0.5, model_type='LL.5')
    pairs = doses.zip(responses).sort_by{|d,e| d }

    max_dose = pairs.collect{|p| p.first.to_f}.max
    min_dose = pairs.collect{|p| p.first.to_f}.min

    max_response = pairs.collect{|p| p.last.to_f}.max
    min_response = pairs.collect{|p| p.last.to_f}.min

    total_range = max_response - min_response

    dose1, response1, dose2, response2 = nil
    if pairs.collect{|p| p.first }.uniq.length > 2 

      data = TSV.setup({}, :key_field => "Sample", :fields => ["Dose", "Effect"], :type => :list, :cast => :to_f)
      pairs.each{|p| 
        k = _k = p.first.to_s
        i = 1
        while data.include? k
          i += 1
          k = _k + ' (' + i.to_s + ')'
        end

        data[k] = p 
      }

      inverse = begin
                  sorted = pairs.sort_by{|p| p.first}
                  sorted[0][1] > sorted[-1][1]
                end

      median_point = max_response * 0.9 if median_point > max_response
      median_point = min_response * 1.1 if median_point < min_response

      response1 = median_point - 0.15 * total_range
      response2 = median_point + 0.15 * total_range
      response1 = 0.05 if response1 < 0.05
      response2 = 0.95 if response2 > 0.95


      if model_type.to_s =~ /least_squares/
        model = R::Model.new "Fit m dm [#{model_type}] #{Misc.digest(data.inspect)}", "log(Effect/(1-Effect)) ~ log(Dose)", nil, "Dose" => :numeric, "Effect" => :numeric, :model_file => model_file
        begin
          data.process "Effect" do |response|
            if response <= 0 
              0.00001
            else
              response
            end
          end
          model.fit(data,'lm')
          mean = Misc.mean responses

          dose1 = adjust_dose(model, Math.log(response1/(1-response1)), min_dose, max_dose, inverse)
          dose2 = adjust_dose(model, Math.log(response2/(1-response2)), min_dose, max_dose, inverse)
          gi50 = adjust_dose(model, Math.log(0.5/(1-0.5)), min_dose, max_dose, inverse)

          dose1, dose2 = self.separate_doses dose1, dose2, min_dose, max_dose

          predict1_info = model.predict_interval(dose1)
          predict2_info = model.predict_interval(dose2)

          response1_info = {}
          response2_info = {}

          predict1_info.each do |k,pred1|
            response1_info[k] =  Math.exp(pred1) / (1+Math.exp(pred1))
          end

          predict2_info.each do |k,pred2|
            response2_info[k] =  Math.exp(pred2) / (1+Math.exp(pred2))
          end

          response1 = response1_info["fit"]
          response2 = response2_info["fit"]

        rescue Exception
          Log.warn "Fit exception: #{$!.message}"
          cmp = pairs[0..-2].zip(pairs[1..-1]).reject{|p1,p2| p1.first == p2.first}.sort_by{|p1,p2| (p1.last - median_point).abs}.first
          dose1, response1, dose2, response2 = cmp.flatten
        end

      else
        R.eval 'library(drc)'
        model = R::Model.new "Fit m dm [#{model_type}] #{Misc.digest(data.inspect)}", "Effect ~ Dose", nil, "Dose" => :numeric, "Effect" => :numeric, :model_file => model_file
        begin
          model_str = ":" << model_type  << "()"
          model.fit(data,'drm', :fct => model_str)
          mean = Misc.mean responses
          
          dose1 = adjust_dose(model, response1, min_dose, max_dose, inverse)
          dose2 = adjust_dose(model, response2, min_dose, max_dose, inverse)
          gi50 = adjust_dose(model, 0.5, min_dose, max_dose, inverse)

          dose1, dose2 = self.separate_doses dose1, dose2, min_dose, max_dose

          response1_info = model.predict_interval(dose1)
          response2_info = model.predict_interval(dose2)

          response1 = response1_info["fit"]
          response2 = response2_info["fit"]

        rescue Exception
          Log.warn "Fit exception: #{$!.message}"
          #Log.exception $!
          cmp = pairs[0..-2].zip(pairs[1..-1]).reject{|p1,p2| p1.first == p2.first}.sort_by{|p1,p2| (p1.last - median_point).abs}.first
          dose1, response1, dose2, response2 = cmp.flatten
        end
      end
    else
      dose1, dose2 = pairs.collect{|d,e| d}.uniq
      response1 = pairs.select{|d,e| d == dose1}.collect{|d,e| e}
      response1 = response1.inject(0){|acc,e| acc += e} / response1.length
      response2 = pairs.select{|d,e| d == dose2}.collect{|d,e| e}
      response2 = response2.inject(0){|acc,e| acc += e} / response2.length
    end

    begin
      max_response = response1 if response1 > max_response
      max_response = response2 if response2 > max_response
      m, dm = CombinationIndex.m_dm(dose1, response1, dose2, response2, max_response)

      if response1_info
        random_samples = CombinationIndex.sample_m_dm(dose1, response1_info, dose2, response2_info, max_response)
        random_samples.select!{|_m,_dm| (m > 0) == (_m > 0)}
      else
        random_samples = []
      end
                   
      [m, dm, dose1, response1, dose2, response2, gi50] + random_samples
    rescue Exception
      Log.warn "M Dm exception: #{$!.message}"
      #Log.exception $!
      [nil, nil]
    end
  end

  def self.ci_value(dose_d1, dm_d1, m_d1, dose_d2, dm_d2, m_d2, response)
    response_ratio = self.response_ratio response

    fit_dose_d1 = (dm_d1 * (response_ratio  ** (1/m_d1)))
    fit_dose_d2 = (dm_d2 * (response_ratio  ** (1/m_d2)))

    term_1 = dose_d1 / fit_dose_d1
    term_2 = dose_d2 / fit_dose_d2

    term_1 + term_2
  end

  def self.ci_value_fit(dose_d1, dose_d2, response, model1, model2, invert_d1, invert_d2)
    fit_dose_d1 = adjust_dose(model1, response.to_f, 0, 10000.0, invert_d1)
    fit_dose_d2 = adjust_dose(model2, response.to_f, 0, 10000.0, invert_d2)

    term1 = dose_d1.to_i/fit_dose_d1
    term2 = dose_d2.to_i/fit_dose_d2

    ci = term1 + term2

    [ci, fit_dose_d1, fit_dose_d2]
  end

  def self.predicted_bliss(response_d1, response_d2)
    response_d1 + response_d2 - (response_d1 * response_d2)
  end

  def self.predicted_hsa(response_d1, response_d2)
    response_d1 < response_d2 ? response_d1 : response_d2
  end

  def self.combination_index(dose_d1_1, response_d1_1, dose_d1_2, response_d1_2, 
                               dose_d2_1, response_d2_1, dose_d2_2, response_d2_2,
                               dose_c_d1, dose_c_d2, response_c)

    m1,dm1 = m_dm(dose_d1_1, response_d1_1, dose_d1_2, response_d1_2)
    m2,dm2 = m_dm(dose_d2_1, response_d2_1, dose_d2_2, response_d2_2)

    ci_value(dose_c_d1, dm1, m1, dose_c_d2, dm2, m2, response_c)
  end

  def self.parse_single_treatment(treatment)
    if treatment =~ /ctrl|starve/
      treatment
    else
      drug_name, drug_dose, set = treatment.match(/(.*)=([^\s]*)(?: set (\d))?/).captures
    end
  end

  def self.parse_combination(treatment)
    if m = treatment.match(/(.+)=(.+)-(.+)=([^\s]+)(?: set (\d))?/)
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = m.captures
    end

    if m = treatment.match(/(.+)-(.+)=(.+)-([^\s]+)(?: set (\d))?/)
      drug_name1, drug_name2, drug_dose1, drug_dose2, set = m.captures
    end

    [drug_name1, drug_dose1, drug_name2, drug_dose2, set]
  end

  def self.extract_drugs_doses_and_responses(tsv, model_dir = nil)
    drug_doses = {}
    drug_responses = {}
    combination_drugs = {}
    combination_doses = {}
    combination_responses = {}

    max = 0
    min = 1000
    TSV.traverse tsv do |treatment, values|
      values = String === values ? values.split("|") : values.inject([]){|acc,e| acc.concat e.to_s.split("|"); acc }
      is_combination = treatment.include? '-'
      values.each do |value|
        value = value.to_f
        max = value if value > max
        min = value if value < min

        if is_combination

          drug_name1, drug_dose1, drug_name2, drug_dose2, set = parse_combination treatment


          if drug_name1 == drug_name2
            drug_doses[set] ||= {}
            drug_responses[set] ||= {}
            drug_doses[set][drug_name1] ||= []
            drug_responses[set][drug_name1] ||= []
            drug_doses[set][drug_name1] << drug_dose1.to_f + drug_dose2.to_f
            drug_responses[set][drug_name1] << value
          else
            combination_doses[set] ||= {}
            combination_drugs[set] ||= {}
            combination_responses[set] ||= {}

            combination_doses[set][treatment] = [drug_dose1.to_f, drug_dose2.to_f]
            combination_drugs[set][treatment] = [drug_name1, drug_name2]
            combination_responses[set][treatment] = value
          end
        else
          next if treatment =~ /ctrl|starve/
          drug_name, drug_dose, set = parse_single_treatment treatment

          drug_doses[set] ||= {}
          drug_responses[set] ||= {}
          drug_doses[set][drug_name] ||= []
          drug_responses[set][drug_name] ||= []
          drug_doses[set][drug_name] << drug_dose.to_f
          drug_responses[set][drug_name] << value
        end
      end
    end

    range = max - min

    drug_info = {}

    drug_doses.keys.each do |set|

      drug_doses[set].keys.each do |drug|
        drug_info[set] ||= {}

        doses = drug_doses[set][drug]
        responses = drug_responses[set][drug].collect{|f| 1 - ( (f - min) / range ) }

        model_file = File.join(model_dir, [drug, set].compact * " set ")
        m, dm, dose1, response1, dose2, response2 = begin
                  CombinationIndex.fit_m_dm doses, responses, model_file
                rescue Exception
                  Log.exception $!
                  [nil, nil]
                end

        drug_info[set][drug] = {:doses => doses, :responses => responses, :dm => dm, :m => m, :dose1 => dose1, :response1 => response1, :dose2 => dose2, :response2 => response2}
      end
    end

    combination_info = {}
    combination_drugs.keys.each do |set|
      combination_drugs[set].each do |treatment,drug_names| 
        combination_info[set] ||= {}

        drug1, drug2 = drug_names
        dose1, dose2 = combination_doses[set][treatment]
        response = combination_responses[set][treatment]
        response = 1 - ((response - min) / range)

        combination_info[set][treatment] = {
          :drug1 => drug1, 
          :drug2 => drug2, 
          :drug1_dose => dose1 ,
          :drug2_dose => dose2 ,
          :response => response,
        }
      end
    end

    [drug_info, combination_info]
  end

end
