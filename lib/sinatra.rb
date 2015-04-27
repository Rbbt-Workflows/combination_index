#wf = Workflow.require_workflow "Miller"
#add_workflow wf, true


#get '/CombinationIndex/combination_index_batch/details/:jobname/:combination' do
#  template_render('CombinationIndex/combination_index_batch/details', @clean_params)
#end


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
  halt 200, {:drug_info => drug_info, :combination_info => combination_info}.to_json
end
