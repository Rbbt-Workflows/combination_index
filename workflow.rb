require 'rbbt-util'
require 'rbbt/workflow'

require_relative 'lib/combination_index'

module CombinationIndex
  extend Workflow

  desc "Compute median-effect statistics"
  input :dose_1, :float, "Dose level 1"
  input :effect_1, :float, "Fraction affected at level 1"
  input :dose_2, :float, "Dose level 2"
  input :effect_2, :float, "Fraction affected at level 2"
  task :m_dm => :array 
  export_exec :m_dm

  desc "Compute combination using median-effect statistics"
  input :dose_d1, :float, "Dose level for first drug"
  input :dm_d1, :float, "Dm of first drug"
  input :m_d1, :float, "Shape of first drug"
  input :dose_d2, :float, "Dose level for second drug"
  input :dm_d2, :float, "Dm of second drug"
  input :m_d2, :float, "Shape of second drug"
  input :effect, :float, "Combination effect"
  task :ci_value => :float 
  export_exec :ci_value

  desc "Compute combination using dose and effects"
  input :dose_d1_1, :float, "Drug 1 dose level 1"
  input :effect_d1_1, :float, "Drug 1 fraction affected at level 1"
  input :dose_d1_2, :float, "Drug 1 dose level 2"
  input :effect_d1_2, :float, "Drug 1 fraction affected at level 2"
  input :dose_d2_1, :float, "Drug 2 dose level 1"
  input :effect_d2_1, :float, "Drug 2 fraction affected at level 1"
  input :dose_d2_2, :float, "Drug 2 dose level 2"
  input :effect_d2_2, :float, "Drug 2 fraction affected level 2"
  input :dose_c_d1, :float, "Drug 1 dose level in combination"
  input :dose_c_d2, :float, "Drug 2 dose level in combination"
  input :effect_c, :float, "Combination effect"
  task :combination_index => :float
  export_exec :combination_index

  input :file, :tsv
  task :model_drugs => :yaml do |file|
    ci_values = {}
    file = file.tsv if Path === file

    if file.fields.length > 1 and file.fields.include? "Dose"
      file = file.unzip("Dose", true, "=")
    end
    file = file.to_flat 

    drug_info, combination_info = 
      CombinationIndex.extract_drugs_doses_and_effects(file, self.file(:models))
    set_info :drugs, drug_info
    set_info :combinations, combination_info

    {:drugs => drug_info, :combinations => combination_info}
  end


  desc "Compute combination index analysis for a single effect over a full compliment of treatments"
  input :file, :tsv, "Synergies"
  task :combination_index_batch => :tsv do |file|
    ci_values = {}
    file = file.tsv if Path === file

    if file.fields.length > 1 and file.fields.include? "Dose"
      file = file.unzip("Dose", true, "=")
    end
    file = file.to_flat 

    drug_info, combination_info = 
      CombinationIndex.extract_drugs_doses_and_effects(file, self.file(:models))

    set_info :drug_info, drug_info
    set_info :combination_info, combination_info

    sets = drug_info.keys

    sets.each do |set|
      ci_values[set] = {}

      next unless drug_info.include? set and combination_info.include? set

      combination_info[set].each do |treatment, info|
        drug1, drug2, dose1, dose2, effect = info.values_at :drug1, :drug2, :drug1_dose, :drug2_dose, :effect

        dm1, m1 = drug_info[set][drug1].values_at :dm, :m
        dm2, m2 = drug_info[set][drug2].values_at :dm, :m
        next if dm1.nil? or dm2.nil?

        ci_value = CombinationIndex.ci_value(dose1, dm1, m1, dose2, dm2, m2, effect)
        ci_value = ci_value.to_s
        ci_value = nil if ci_value.to_s == "NaN"
        ci_values[set][treatment] = ci_value
      end
    end
    
    tsv = {}
    ci_values.each do |set, hash| tsv.merge! hash end
    TSV.setup(tsv, :type => :single, :key_field => "Combination", :fields => [file.fields.first], :cast => :to_f)

    flat = tsv.to_double

    flat.cast = nil

    flat.add_field "Compound 1" do |treatment,values|
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
      drug_name1
    end

    flat.add_field "Compound 2" do |treatment,values|
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
      drug_name2
    end

    flat.add_field "Dose 1" do |treatment,values|
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
      drug_dose1
    end

    flat.add_field "Dose 2" do |treatment,values|
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
      drug_dose2
    end

    flat.add_field "Set" do |treatment,values|
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
      set
    end

    flat.process file.fields.first do |ci|
      case ci
      when 0, 0.0
        nil
      when ""
        nil
      else
        ci
      end
    end


    Open.write(file(:flat), flat.to_s)

    tsv
  end
  export_exec :combination_index_batch

  desc "Compute combination index analysis in a multiple effects over a full compliment of treatments"
  input :file, :tsv, "Synergies"
  task :combination_index_multiple => :tsv do |file|
    file = TSV.open(file) unless TSV === file
    file = file.to_list unless file.type == :list

    fields = file.fields
    result = TSV.setup(file.keys, :key_field => "Combination", :fields => [], :type => :list, :cast => :to_f)
    drug_info = {}
    combination_info = {}
    FileUtils.mkdir_p self.file(:models)
    fields.each do |field|
      job = CombinationIndex.job(:combination_index_batch, field, :file => file.slice(field))
      res = job.run
      drug_info[field] = job.info[:drug_info]
      combination_info[field] = job.info[:combination_info]

      res = res.to_list
      res.fields = [field]

      FileUtils.cp_r job.file(:models).find, self.file(:models)[field].find

      result = result.attach res
    end

    set_info :drug_info, drug_info
    set_info :combination_info, combination_info

    result = result.select{|k,v| v and v.any?}
    result.cast = :to_f
    result
  end
  export_asynchronous :combination_index_multiple
end

require_relative 'lib/tasks/CI.rb'
