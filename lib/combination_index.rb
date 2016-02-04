require 'rbbt/util/R/model'

R.eval_a 'library(drc)'
module CombinationIndex

  def self.effect_ratio(effect, max = 1.0)
    effect / (max.to_f - effect)
  end

  def self.additive_dose(level, blue_dose, red_dose, blue_m, blue_dm, red_m, red_dm)
    ratio = self.effect_ratio(level); 
    t1 =  blue_dose/(blue_dm*(ratio**(1/blue_m)))
    t2 =  red_dose/(red_dm*(ratio**(1/red_m)))
    (blue_dose+red_dose)/(t1 + t2)
  end

  def self.m_dm(dose_1, effect_1, dose_2, effect_2, max_effect = 1)
    max_effect = 1

    e_ratio1 = self.effect_ratio effect_1, max_effect
    e_ratio2 = self.effect_ratio effect_2, max_effect

    le1 = Math.log(e_ratio1)
    le2 = Math.log(e_ratio2)

    ld1 = Math.log(dose_1)
    ld2 = Math.log(dose_2)

    m = ( le1 - le2 ) / (ld1 - ld2)
    dm = dose_1/ ((e_ratio1) ** (1/m))

    raise "Negative median drug dose level" if dm <= 0

    [m, dm]
  end

  def self.sample_m_dm(dose_1, effect1_info, dose_2, effect2_info, max_effect)
    fit1 = effect1_info["fit"]
    fit2 = effect2_info["fit"]

    sd1 = (effect1_info["upper"] - effect1_info["fit"])/1.96
    sd2 = (effect2_info["upper"] - effect2_info["fit"])/1.96
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

  def self.adjust_dose(model, effect, min_dose, max_dose, inverse=false)
    dose = min_dose + (max_dose - min_dose)/2

    real_max_dose = max_dose
    real_min_dose = min_dose

    new_effect = model.predict(dose)
    delta = new_effect - effect
    while delta.abs > 0.01 and real_max_dose - dose > real_max_dose / 100 and dose - real_min_dose > real_min_dose / 100
      if (delta < 0 and not inverse) or (delta > 0 and inverse)
        min_dose = dose
        dose = dose + (max_dose - dose) / 2
      else
        max_dose = dose
        dose = dose - (dose - min_dose) / 2
      end
      new_effect = model.predict(dose)
      delta = new_effect - effect
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

  def self.fit_m_dm(doses, effects, model_file = nil, median_point = 0.5, model_type='LL.5')
    pairs = doses.zip(effects).sort_by{|d,e| d }

    max_dose = pairs.collect{|p| p.first.to_f}.max
    min_dose = pairs.collect{|p| p.first.to_f}.min

    max_effect = pairs.collect{|p| p.last.to_f}.max
    min_effect = pairs.collect{|p| p.last.to_f}.min

    total_range = max_effect - min_effect

    dose1, effect1, dose2, effect2 = nil
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

      median_point = max_effect * 0.9 if median_point > max_effect
      median_point = min_effect * 1.1 if median_point < min_effect

      effect1 = median_point - 0.15 * total_range
      effect2 = median_point + 0.15 * total_range
      effect1 = 0.05 if effect1 < 0.05
      effect2 = 0.95 if effect2 > 0.95


      if model_type.to_s =~ /least_squares/
        model = R::Model.new "Fit m dm [#{model_type}] #{Misc.digest(data.inspect)}", "log(Effect/(1-Effect)) ~ log(Dose)", nil, "Dose" => :numeric, "Effect" => :numeric, :model_file => model_file
        begin
          data.process "Effect" do |effect|
            if effect <= 0 
              0.00001
            else
              effect
            end
          end
          model.fit(data,'lm')
          mean = Misc.mean effects

          dose1 = adjust_dose(model, Math.log(effect1/(1-effect1)), min_dose, max_dose, inverse)
          dose2 = adjust_dose(model, Math.log(effect2/(1-effect2)), min_dose, max_dose, inverse)
          gi50 = adjust_dose(model, Math.log(0.5/(1-0.5)), min_dose, max_dose, inverse)

          dose1, dose2 = self.separate_doses dose1, dose2, min_dose, max_dose

          predict1_info = model.predict_interval(dose1)
          predict2_info = model.predict_interval(dose2)

          effect1_info = {}
          effect2_info = {}

          predict1_info.each do |k,pred1|
            effect1_info[k] =  Math.exp(pred1) / (1+Math.exp(pred1))
          end

          predict2_info.each do |k,pred2|
            effect2_info[k] =  Math.exp(pred2) / (1+Math.exp(pred2))
          end

          effect1 = effect1_info["fit"]
          effect2 = effect2_info["fit"]

        rescue Exception
          Log.warn "Fit exception: #{$!.message}"
          cmp = pairs[0..-2].zip(pairs[1..-1]).reject{|p1,p2| p1.first == p2.first}.sort_by{|p1,p2| (p1.last - median_point).abs}.first
          dose1, effect1, dose2, effect2 = cmp.flatten
        end

      else
        R.eval 'library(drc)'
        model = R::Model.new "Fit m dm [#{model_type}] #{Misc.digest(data.inspect)}", "Effect ~ Dose", nil, "Dose" => :numeric, "Effect" => :numeric, :model_file => model_file
        begin
          model_str = ":" << model_type  << "()"
          model.fit(data,'drm', :fct => model_str)
          mean = Misc.mean effects
          
          dose1 = adjust_dose(model, effect1, min_dose, max_dose, inverse)
          dose2 = adjust_dose(model, effect2, min_dose, max_dose, inverse)
          gi50 = adjust_dose(model, 0.5, min_dose, max_dose, inverse)

          dose1, dose2 = self.separate_doses dose1, dose2, min_dose, max_dose

          effect1_info = model.predict_interval(dose1)
          effect2_info = model.predict_interval(dose2)

          effect1 = effect1_info["fit"]
          effect2 = effect2_info["fit"]

        rescue Exception
          Log.warn "Fit exception: #{$!.message}"
          Log.exception $!
          cmp = pairs[0..-2].zip(pairs[1..-1]).reject{|p1,p2| p1.first == p2.first}.sort_by{|p1,p2| (p1.last - median_point).abs}.first
          dose1, effect1, dose2, effect2 = cmp.flatten
        end
      end
    else
      dose1, dose2 = pairs.collect{|d,e| d}.uniq
      effect1 = pairs.select{|d,e| d == dose1}.collect{|d,e| e}
      effect1 = effect1.inject(0){|acc,e| acc += e} / effect1.length
      effect2 = pairs.select{|d,e| d == dose2}.collect{|d,e| e}
      effect2 = effect2.inject(0){|acc,e| acc += e} / effect2.length
    end

    begin
      max_effect = effect1 if effect1 > max_effect
      max_effect = effect2 if effect2 > max_effect
      m, dm = CombinationIndex.m_dm(dose1, effect1, dose2, effect2, max_effect)

      if effect1_info
        random_samples = CombinationIndex.sample_m_dm(dose1, effect1_info, dose2, effect2_info, max_effect)
        random_samples.select!{|_m,_dm| (m > 0) == (_m > 0)}
      else
        random_samples = []
      end
                   
      [m, dm, dose1, effect1, dose2, effect2, gi50] + random_samples
    rescue Exception
      Log.warn "M Dm exception: #{$!.message}"
      Log.exception $!
      [nil, nil]
    end
  end

  def self.ci_value(dose_d1, dm_d1, m_d1, dose_d2, dm_d2, m_d2, effect)
    effect_ratio = self.effect_ratio effect

    term_1 = dose_d1 / (dm_d1 * (effect_ratio  ** (1/m_d1)))
    term_2 = dose_d2 / (dm_d2 * (effect_ratio  ** (1/m_d2)))

    term_1 + term_2
  end

  def self.ci_value_fit(dose_d1, dose_d2, effect, model1, model2, invert_d1, invert_d2)
    fit_dose_d1 = adjust_dose(model1, effect.to_f, 0, 10000.0, invert_d1)
    fit_dose_d2 = adjust_dose(model2, effect.to_f, 0, 10000.0, invert_d2)

    term1 = dose_d1.to_i/fit_dose_d1
    term2 = dose_d2.to_i/fit_dose_d2

    ci = term1 + term2

    [ci, fit_dose_d1, fit_dose_d2]
  end

  def self.combination_index(dose_d1_1, effect_d1_1, dose_d1_2, effect_d1_2, 
                               dose_d2_1, effect_d2_1, dose_d2_2, effect_d2_2,
                               dose_c_d1, dose_c_d2, effect_c)

    m1,dm1 = m_dm(dose_d1_1, effect_d1_1, dose_d1_2, effect_d1_2)
    m2,dm2 = m_dm(dose_d2_1, effect_d2_1, dose_d2_2, effect_d2_2)

    ci_value(dose_c_d1, dm1, m1, dose_c_d2, dm2, m2, effect_c)
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

  def self.extract_drugs_doses_and_effects(tsv, model_dir = nil)
    drug_doses = {}
    drug_effects = {}
    combination_drugs = {}
    combination_doses = {}
    combination_effects = {}

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
            drug_effects[set] ||= {}
            drug_doses[set][drug_name1] ||= []
            drug_effects[set][drug_name1] ||= []
            drug_doses[set][drug_name1] << drug_dose1.to_f + drug_dose2.to_f
            drug_effects[set][drug_name1] << value
          else
            combination_doses[set] ||= {}
            combination_drugs[set] ||= {}
            combination_effects[set] ||= {}

            combination_doses[set][treatment] = [drug_dose1.to_f, drug_dose2.to_f]
            combination_drugs[set][treatment] = [drug_name1, drug_name2]
            combination_effects[set][treatment] = value
          end
        else
          next if treatment =~ /ctrl|starve/
          drug_name, drug_dose, set = parse_single_treatment treatment

          drug_doses[set] ||= {}
          drug_effects[set] ||= {}
          drug_doses[set][drug_name] ||= []
          drug_effects[set][drug_name] ||= []
          drug_doses[set][drug_name] << drug_dose.to_f
          drug_effects[set][drug_name] << value
        end
      end
    end

    range = max - min

    drug_info = {}

    drug_doses.keys.each do |set|

      drug_doses[set].keys.each do |drug|
        drug_info[set] ||= {}

        doses = drug_doses[set][drug]
        effects = drug_effects[set][drug].collect{|f| 1 - ( (f - min) / range ) }

        model_file = File.join(model_dir, [drug, set].compact * " set ")
        m, dm, dose1, effect1, dose2, effect2 = begin
                  CombinationIndex.fit_m_dm doses, effects, model_file
                rescue Exception
                  Log.exception $!
                  [nil, nil]
                end

        drug_info[set][drug] = {:doses => doses, :effects => effects, :dm => dm, :m => m, :dose1 => dose1, :effect1 => effect1, :dose2 => dose2, :effect2 => effect2}
      end
    end

    combination_info = {}
    combination_drugs.keys.each do |set|
      combination_drugs[set].each do |treatment,drug_names| 
        combination_info[set] ||= {}

        drug1, drug2 = drug_names
        dose1, dose2 = combination_doses[set][treatment]
        effect = combination_effects[set][treatment]
        effect = 1 - ((effect - min) / range)

        combination_info[set][treatment] = {
          :drug1 => drug1, 
          :drug2 => drug2, 
          :drug1_dose => dose1 ,
          :drug2_dose => dose2 ,
          :effect => effect,
        }
      end
    end

    [drug_info, combination_info]
  end

  def self.import_expanded(tsv, scale, invert)
    drug_info = {}
    combination_info = {}

    if scale
      values = tsv.values.collect{|v| v[1] }.flatten.uniq.collect{|v| v.to_f}
      max = values.max + 0.0001
      min = values.min - 0.0001
    end

    tsv.through do |k,values|
      if k.include? '-'
        combination_info[k] ||= []
        Misc.zip_fields(values).each do |doses, response|
          blue_dose, red_dose = doses.split("-")
          response = response.to_f
          response = (response - min) / (max - min) if scale 
          response = 1.0 - [1.0, response].min if invert
          response = response.round(5)
          combination_info[k] << [blue_dose.to_f, red_dose.to_f, response]
        end
      else
        drug_info[k] ||= []
        Misc.zip_fields(values).each do |dose, response|
          response = response.to_f
          response = (response - min) / (max - min) if scale 
          response = 1.0 - [1.0, response].min if invert
          response = response.round(5)
          drug_info[k] << [dose.to_f, response]
        end
      end
    end

    [drug_info, combination_info]
  end

  def self.import_compact(tsv, scale, invert)
    drug_info = {}
    combination_info = {}

    if scale
      values = tsv.values.collect{|v| v }.flatten.uniq.collect{|v| v.to_f}
      max = values.max
      min = values.min
    end

    tsv.through do |k,values|
      values = values[0]
      values = [values] unless Array === values
      if k =~ /\s*set\s*(\d+)/
        k = $`
        set = $1
      else
        set = nil
      end

      begin
        if k.include? '-'
          blue_drug_info, red_drug_info = k.split("-")

          blue_drug, blue_dose = blue_drug_info.split("=")
          red_drug, red_dose = red_drug_info.split("=")
          if blue_drug == red_drug

            k = [blue_drug, (red_dose.to_f + blue_dose.to_f).to_s] * "="
            raise TryAgain
          end

          combination = [blue_drug, red_drug] * "-"
          combination_info[combination] ||= []

          values.each do |response|
            response = response.to_f
            blue_dose = blue_dose.to_f
          red_dose = red_dose.to_f

          response = (response - min) / (max - min) if scale 
          response = 1.0 - [1.0, response].min if invert
          response = response.round(5)

          combination_info[combination] << [blue_dose.to_f, red_dose.to_f, response, set]
          end
        else
          drug, dose = k.split("=")

          drug_info[drug] ||= []

          values.each do |response|
            response = response.to_f
            dose = dose.to_f

            response = (response - min) / (max - min) if scale 
            response = 1.0 - [1.0, response].min if invert
            response = response.round(5)

            drug_info[drug] << [dose, response, set]
          end
        end
      rescue TryAgain
        retry
      end
    end

    [drug_info, combination_info]
  end
end
