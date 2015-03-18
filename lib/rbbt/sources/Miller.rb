require 'rbbt-util'
require 'rbbt/resource'

require 'rbbt/workflow'
Workflow.require_workflow "Translation" 

module Miller
  extend Resource
  self.subdir = 'share/databases/Miller'

  def self.organism(org="Hsa")
    Organism.default_code(org)
  end

  Miller.claim Miller.original_data, :url, "http://cbio.mskcc.org/~miller/SI/Miller_et_al_2013_Science_Signaling_RPPA_raw_data.txt"

  Miller.claim Miller.identifiers, :proc do
    tsv = Miller['.source'].identifiers_AF.tsv :type => :double
    ensembl_codes = 
    tsv.add_field "Ensembl Gene ID" do |code,values|
      names = values.first
    end

  end


  Miller.claim Miller.id_values, :proc do 
    path = Miller.original_data
    tsv = path.tsv :type => :list, :merge => true, 
      :sep2 => "NONE", :header_hash => '', :grep => "#", :invert_grep => true,
      :fix => Proc.new{|line|
          parts = line.split "\t"
          set = parts[1]
          treatment = parts[2]
          parts[2] = treatment.gsub("|","=").gsub(",","-").gsub(",","-") + ' set ' + set
          parts * "\t"
    }
    tsv
  end

  Miller.claim Miller.antibody_info, :proc do 

    fields = Miller.id_values.fields
    antibodies = fields.select{|f| f =~ /GBL/ }
    tsv = TSV.setup(antibodies, :key_field => "Antibody code", :fields => [], :type => :list)

    tsv.add_field "Clean name" do |ab,v|
      field = ab.dup
      field.sub!(/MEK1-2-/, 'MEK1/2_')
      field.sub!(/MEK1_2_/, 'MEK1/2_')
      field.sub!(/_*\((\w)\)_*/, '_\1_')
      field.sub!(/([^)]+)\(([^)]+)\)/, '\1_\2')
      field.sub!(/_([VCcv])_/, '_')

      field.sub!(/mouse_/, 'mouse-')
      field.sub!(/(?:active|cleaved|clv).(\w+)/i, 'clv-\1')

      field.sub!(/^([a-z]+)_([a-z]+)_/i, '\1 \2_') unless field =~ /cleave/i 
      field.sub!(/(p[A-Z])(\d+)_(\d+)/, '\1\2-\1\3')

      field.sub!(/ER_/, 'ER/SP1_')
      field.sub!(/SMAC_DIABO/, 'SMAC/DIABLO')
      field.sub!(/GSK3a_b/, 'GSK3A/B')
      field.sub!("3Beta", '3-beta')
      field.sub!("3-Zeta", '3-zeta')
      field.sub!("PAI-1", 'PAI1')
      field.sub!("4EB1", '4EBP1')
      field.sub!("alpha Tubulin", 'TUBA1A')
      field.sub!("CaseinKinase", 'CSNK1A1')
      field.sub!("YBI", 'YB1')
      field.sub!("c-JUN", 'JUN')
      field.sub!("1GFBP2", 'IGFBP2')

      field
    end

    tsv.add_field "Gene code" do |ab,v|
      name = v.first
      name.split("_").first
    end

    identifiers = Miller.identifiers.tsv :type => :single
    ensembl_codes = Translation.job(:tsv_translate, "Miller", :format => "Ensembl Gene ID", :genes => identifiers.values.flatten.compact, :organism => organism).run
    tsv.add_field "Ensembl Gene ID" do |ab,v|
      gene = v[1]
      fixed = identifiers[gene] || gene

      ensembl_codes[fixed]
    end

    tsv.add_field "PTM" do |ab,v|
      name = v.first
      gene, ptm, gbl = name.split("_")
      gbl ? ptm : "abundance"
    end

    gene_symbols = Translation.job(:tsv_translate, "Miller", :format => "Associated Gene Name", :genes => tsv.slice("Ensembl Gene ID").values.flatten.compact, :organism => organism).run
    tsv.add_field "Cannonical" do |ab,v|
      clean_name, gene_code, ens, ptm = v
      symbol = gene_symbols[ens]
      [symbol, ptm] * ":"
    end

    tsv.add_field "Slide code" do |ab,v|
      name = v.first
      gene, ptm, gbl = name.split("_")
      gbl ? gbl : ptm
    end

    tsv
  end

  Miller.claim Miller.sample_values, :proc do 
    antibody_info = Miller.antibody_info.tsv
    Miller.id_values.tsv :key_field => "Condition", :fields => antibody_info.keys, :cast => :to_f, :type => :double, :merge => true
  end

  Miller.claim Miller.experiments, :proc do
    tsv = Miller.sample_values.tsv
    dumper = TSV.traverse tsv, :into => :dumper do |k,values|
      k = k.first if Array === k
      result = []
      result.extend MultipleResult
      Misc.zip_fields(values).each_with_index do |v,i| 
        result << [k + " rep #{i}", v]
      end
      result
    end

    tsv  = TSV.open dumper.stream
    tsv.cast = nil
    tsv.key_field = "Experiment"

    tsv = tsv.to_list

    tsv.add_field "Set" do |k,v|
      k.match(/set (\d+)/)[1]
    end

    tsv.add_field "Perturbation" do |k,v|
      k.match(/(.*) set /)[1]
    end

    tsv.namespace = Miller.organism

    tsv
  end

  Miller.claim Miller.drug_targets, :proc do
    targets =  Hash[*Miller.original_data.open(:grep => "Targets of drug").read.split("\n").first.scan(/([A-Z]{2}): ([^,.]+)/).flatten]
    TSV.setup targets, :key_field => "Compound", :fields => ["Target"], :type => :single
    drugs =  Hash[*Miller.original_data.open(:grep => "The drugs used").read.split("\n").first.scan(/([^ :]+): ([^,.]+)/).flatten]
    TSV.setup drugs, :key_field => "Target", :fields => ["Compound"], :type => :single
    # Targets of drug are; AG: IGF1R, AK: AKT, ER: ERK, GF: EGFR, HN: HDAC, PD:
    # PDGFR, PI: PI3K, RT: PKC, RY: CDK4, SL: MEK, SR: SRC, ST: STAT3, SU: MET,
    # RP: mTOR.
    # # The drugs used were; IGF1R: AG538, AKT1/2: AKT 1/2 Inh, ERK1/2:
    # FR180204, EGFR: Gefitinib, HDAC: HNHA, PDGFR: PDGFR TKI III,
    # PI3K(PIK3CA/2A/2B): PI3Ka Inh IV, mTOR: Rapamycin,
    merged = targets.to_list.attach drugs.to_list

    identifiers = Miller.identifiers.tsv :type => :double
    ensembl_codes = Translation.job(:tsv_translate, "Miller", :format => "Ensembl Gene ID", :genes => (targets.values + identifiers.values.flatten.compact), :organism => organism).run
    merged.add_field "Ensembl Gene ID" do |compound,values|
      target = values["Target"]

      fixed = identifiers[target] || [target]
      ensembl_codes.values_at *fixed.flatten
    end
    merged
  end

  Miller.claim Miller.survival_values, :proc do
    file = Rbbt.data.original_viability_values.find(:lib)

    single_compound_dose_effects = {}
    dose_levels = {}
    synergy_dose_effects = {}
    TSV.traverse file, :type => :list do |experiment,values|
      condition, dose, effect, std = values
      if condition =~ /[A-Z]{2}.[A-Z]{2}.C\d/
        c1, c2, level = condition.split(".")
        synergy_dose_effects[[c1,c2]] ||= {}
        synergy_dose_effects[[c1,c2]][level] ||= []
        synergy_dose_effects[[c1,c2]][level] << [effect, std]
      else
        c1, level = condition.split(".")

        dose_levels[c1] ||= {}
        dose_levels[c1][level] = dose.to_f
        single_compound_dose_effects[c1] ||= {}
        single_compound_dose_effects[c1][dose] ||= []
        single_compound_dose_effects[c1][dose] << [effect, std]
      end
    end

    tsv = TSV.setup({}, :type => :double, :key_field => "Treatment", :fields => ["Dose", "Effect", "STD"])

    single_compound_dose_effects.each do |compound,info|
      info.each do |dose, value_list|
        value_list.uniq.each do |values|
          eff, std = values
          tsv.zip_new compound, [dose.to_f, eff.to_f, std.to_f]
        end
      end
    end

    synergy_dose_effects.each do |synergy,info|
      c1, c2 = synergy
      compound = [c1,c2] * "-"
      info.each do |level,value_list|
        value_list.uniq.each do |values|
          dose = [dose_levels[c1][level], dose_levels[c2][level]] * "-"
          eff, std = values
          tsv.zip_new compound, [dose, eff.to_f, std.to_f]
        end
      end
    end

    tsv.to_s
  end

  Miller.claim Miller.RPPA.data, :proc do
    tsv = Miller.sample_values.tsv
    dumper = TSV.traverse tsv, :into => :dumper do |k,values|
      k = k.first if Array === k
      result = []
      result.extend MultipleResult
      Misc.zip_fields(values).each_with_index do |v,i| 
        result << [k + " rep #{i}", v]
      end
      result
    end

    tsv  = TSV.open dumper.stream
    tsv.cast = nil
    tsv.key_field = "Experiment"

    tsv = tsv.to_list
    tsv.to_s
  end

  Miller.claim Miller.RPPA.identifiers, :proc do
    Miller.antibody_info.open
  end

  Miller.claim Miller.RPPA.labels, :proc do
    tsv = TSV.setup({}, :key_field => "Experiment", :fields => ["Perturbation", "Compound", "Dose", "Set", "Replicate"], :type => :list)
    data = Miller.RPPA.data.tsv
    data.keys.each do |k|
      perturbation, _sep, rest = k.partition " "
      set, rep = rest.scan(/(... \d+)/)
      compound = perturbation.scan(/(\w+)=/).flatten * "-"
      dose = perturbation.scan(/=([0-9\.]+)/).flatten * "-"
      values = [perturbation, compound, dose, set, rep]
      tsv[k] = values
    end
    tsv.to_s
  end
  
  Miller.claim Miller.Viability.data, :proc do

    file = Miller.original_viability_values

    single_compound_dose_effects = {}
    dose_levels = {}
    synergy_dose_effects = {}
    TSV.traverse file, :type => :list do |experiment,values|
      condition, dose, effect, std = values
      if condition =~ /[A-Z]{2}.[A-Z]{2}.C\d/
        c1, c2, level = condition.split(".")
        synergy_dose_effects[[c1,c2]] ||= {}
        synergy_dose_effects[[c1,c2]][level] = [effect, std]
      else
        c1, level = condition.split(".")

        dose_levels[c1] ||= {}
        dose_levels[c1][level] = dose.to_f
        single_compound_dose_effects[c1] ||= {}
        single_compound_dose_effects[c1][dose] = [effect, std]
      end
    end

    tsv = TSV.setup({}, :type => :double, :key_field => "Compound", :fields => ["Dose", "Effect", "STD"])

    single_compound_dose_effects.each do |compound,info|
      info.each do |dose, values|
        eff, std = values
        tsv.zip_new compound, [dose.to_f, eff.to_f, std.to_f]
      end
    end

    synergy_dose_effects.each do |synergy,info|
      c1, c2 = synergy
      compound = [c1,c2] * "-"
      info.each do |level,values|
        dose = [dose_levels[c1][level], dose_levels[c2][level]] * "-"
        eff, std = values
        tsv.zip_new compound, [dose, eff.to_f, std.to_f]
      end
    end

    tsv.to_s
  end
end
