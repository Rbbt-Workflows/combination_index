wf = Workflow.require_workflow "Miller"
add_workflow wf, true

require 'rbbt/util/R/svg'

get '/CombinationIndex/combination_index_batch/details/:jobname/:combination' do
  template_render('CombinationIndex/combination_index_batch/details', @clean_params)
end
