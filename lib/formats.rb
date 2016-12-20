require 'rbbt/tsv/excel'
module CombinationIndex
  def self.export_excel(tsv, file, unmerge = true, expand = true)
    if expand
      new = TSV.setup({}, :key_field => "Drug", :fields => ["Second drug", "Drug dose", "Sencond drug dose", "Response"], :type => :double, :cast => :to_f)
      TSV.traverse tsv, :into => new do |key, values|
        blue_drug, red_drug = key.split(CombinationIndex::COMBINATION_SEP)
        doses, responses = values
        red_drug = '' if red_drug.nil?

        blue_doses = []
        red_doses = []
        doses.each do |dose|
          blue_dose, red_dose = dose.to_s.split(CombinationIndex::COMBINATION_SEP)
          red_dose = '' if red_dose.nil?
          blue_doses << blue_dose
          red_doses << red_dose 
        end

        [blue_drug, [[red_drug] * red_doses.length, blue_doses, red_doses, responses]]
      end

      tsv = new
    end
    tsv.excel(file, :sheet => "Sheet1", :unmerge => unmerge)
  end

  def self.export_tsv(tsv, file, unmerge = true, expand = true)
    if expand
      new = TSV.setup({}, :key_field => "Drug", :fields => ["Second drug", "Drug dose", "Sencond drug dose", "Response"], :type => :double, :cast => :to_f)
      TSV.traverse tsv, :into => new do |key, values|
        blue_drug, red_drug = key.split(CombinationIndex::COMBINATION_SEP)
        doses, responses = values
        red_drug = '' if red_drug.nil?

        blue_doses = []
        red_doses = []
        doses.each do |dose|
          blue_dose, red_dose = dose.to_s.split(CombinationIndex::COMBINATION_SEP)
          red_dose = '' if red_dose.nil?
          blue_doses << blue_dose
          red_doses << red_dose 
        end

        [blue_drug, [[red_drug] * red_doses.length, blue_doses, red_doses, responses]]
      end

      tsv = new
    end

    Open.write(file, tsv.to_s(nil, false, unmerge))
  end

  #def self.import_compact(tsv, scale, invert)
  #  drug_info = {}
  #  combination_info = {}

  #  if scale
  #    values = tsv.values.collect{|v| v }.flatten.uniq.collect{|v| v.to_f}
  #    max = values.max
  #    min = values.min
  #  end

  #  tsv.through do |k,values|
  #    values = values[0]
  #    values = [values] unless Array === values
  #    if k =~ /\s*set\s*(\d+)/
  #      k = $`
  #      set = $1
  #    else
  #      set = nil
  #    end

  #    begin
  #      if k.include? '-'
  #        blue_drug_info, red_drug_info = k.split("-")

  #        blue_drug, blue_dose = blue_drug_info.split("=")
  #        red_drug, red_dose = red_drug_info.split("=")
  #        if blue_drug == red_drug

  #          k = [blue_drug, (red_dose.to_f + blue_dose.to_f).to_s] * "="
  #          raise TryAgain
  #        end

  #        combination = [blue_drug, red_drug] * "-"
  #        combination_info[combination] ||= []

  #        values.each do |response|
  #          response = response.to_f
  #          blue_dose = blue_dose.to_f
  #        red_dose = red_dose.to_f

  #        response = (response - min) / (max - min) if scale 
  #        response = 1.0 - [1.0, response].min if invert
  #        response = response.round(5)

  #        combination_info[combination] << [blue_dose.to_f, red_dose.to_f, response, set]
  #        end
  #      else
  #        drug, dose = k.split("=")

  #        drug_info[drug] ||= []

  #        values.each do |response|
  #          response = response.to_f
  #          dose = dose.to_f

  #          response = (response - min) / (max - min) if scale 
  #          response = 1.0 - [1.0, response].min if invert
  #          response = response.round(5)

  #          drug_info[drug] << [dose, response, set]
  #        end
  #      end
  #    rescue TryAgain
  #      retry
  #    end
  #  end

  #  [drug_info, combination_info]
  #end

  def self.import_expanded(tsv, scale, invert)
    drug_info = {}
    combination_info = {}

    Log.tsv tsv
    ppp tsv.to_s
    if scale
      values = tsv.values.collect{|v| v[1] }.flatten.uniq.collect{|v| v.to_f}
      max = values.max + 0.0001
      min = values.min - 0.0001
    end

    tsv.through do |k,values|
      if k.include? CombinationIndex::COMBINATION_SEP
        combination_info[k] ||= []
        Misc.zip_fields(values).each do |doses, response|
          blue_dose, red_dose = doses.split(CombinationIndex::COMBINATION_SEP)
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

  def self.import(content, excel, scale, invert)
    if excel
     tsv = TmpFile.with_file(content, true, :extension => excel) do |excelfile|
        TSV.excel(excelfile, :sep2 => /,\s*/, :merge => true, :zipped => true, :one2one => true)
      end
    else
      tsv = TSV.open(content.strip, :merge => true, :zipped => true, :one2one => true)
    end

    Log.tsv tsv
    if tsv.fields.length < 4
      self.import_expanded(tsv, scale, invert)
    else
      new = TSV.setup({}, :key_field => "Drug", :fields => ["Dose", "Response"], :type => :double)

      TSV.traverse tsv, :into => new do |drug1, values|
        res = []
        Misc.zip_fields(values).each do |drug2, dose1, dose2, response|
          if drug2
            key = [drug1, drug2] * CombinationIndex::COMBINATION_SEP
            dose = [dose1.to_s, dose2.to_s] * CombinationIndex::COMBINATION_SEP
            res << [key, [dose, response]] 
          else
            key = drug1
            dose = dose1
            res << [key, [dose, response]] 
          end
        end
        res.extend MultipleResult
        iii res
        res
      end

      self.import_expanded(new, scale, invert)
    end
  end
end
