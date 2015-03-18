wf = Workflow.require_workflow "Miller"
add_workflow wf, true

require 'rbbt/util/R/svg'

get '/CombinationIndex/combination_index_batch/details/:jobname/:combination' do
  template_render('CombinationIndex/combination_index_batch/details', @clean_params)
end


post '/import' do
  invert = prepare_input @clean_params, :invert, :boolean
  scale = prepare_input @clean_params, :scale, :boolean
  content = prepare_input @clean_params, :file, :file

  tsv = TSV.open(content)
  if tsv.fields.include? "Dose"
    drug_info, combination_info = CombinationIndex.import_expanded(tsv, scale, invert)
  else
    drug_info, combination_info = CombinationIndex.import_compact(tsv, scale, invert)
  end
  #drug_info = {}
  #combination_info = {}

  #if scale
  #  values = tsv.values.collect{|v| v[1] }.flatten.uniq.collect{|v| v.to_f}
  #  max = values.max
  #  min = values.min
  #end

  #tsv.through do |k,values|
  #  if k.include? '-'
  #    combination_info[k] ||= []
  #    values.zip_fields.each do |doses, response|
  #      blue_dose, red_dose = doses.split("-")
  #      response = response.to_f
  #      response = (response - min) / (max - min) if scale 
  #      response = 1.0 - [1.0, response].min if invert
  #      response = response.round(5)
  #      combination_info[k] << [blue_dose.to_f, red_dose.to_f, response]
  #    end
  #  else
  #    drug_info[k] ||= []
  #    values.zip_fields.each do |dose, response|
  #      response = response.to_f
  #      response = (response - min) / (max - min) if scale 
  #      response = 1.0 - [1.0, response].min if invert
  #      response = response.round(5)
  #      drug_info[k] << [dose.to_f, response]
  #    end
  #  end
  #end

  halt 200, {:drug_info => drug_info, :combination_info => combination_info}.to_json
end
