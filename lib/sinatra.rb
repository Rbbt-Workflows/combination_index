#wf = Workflow.require_workflow "Miller"
#add_workflow wf, true


#get '/CombinationIndex/combination_index_batch/details/:jobname/:combination' do
#  template_render('CombinationIndex/combination_index_batch/details', @clean_params)
#end

module NumericValue
  format = ["CI", "CI low", "CI high"]
end

$title = "CImbinator" if $title == "CombinationIndex"

require 'formats'

post '/import' do
  filename = @clean_params["file__param_file"][:filename] if @clean_params["file__param_file"]
  invert = prepare_input @clean_params, :invert, :boolean
  scale = prepare_input @clean_params, :scale, :boolean
  content = prepare_input @clean_params, :file, :file

  excel = (filename && filename.include?('.xls')) ? filename.split(".").last : false

  begin
    drug_info, combination_info = CombinationIndex.import(content, excel, scale, invert)
    halt 200, {:drug_info => drug_info, :combination_info => combination_info}.to_json
  rescue
    Log.exception $!
    halt 500, "Could not parse content"
  end
end

post '/excel' do
  content = prepare_input @clean_params, :tsv, :file
  tsv = TSV.open(content.strip, :sep => /\s+/, :merge => true)
  TmpFile.with_file(nil, false, :extension => 'xlsx') do |tmp|
    CombinationIndex.export_excel(tsv, tmp, true, true)
    require 'base64'
    Base64.encode64(Open.read(tmp, :mode => 'rb'))
  end
end

post '/export' do
  format = @clean_params[:format]
  compact = @clean_params[:compact]
  content = prepare_input @clean_params, :tsv, :file

  tsv = TSV.open(content.strip, :sep => /\s/, :merge => true)

  case compact
  when 'none'
    unmerge, expand = true, true
  when 'columns'
    unmerge, expand = true, false
  else
    unmerge, expand = false, false 
  end

  extension = format == 'excel' ? 'xlsx' : 'tsv'
  TmpFile.with_file(nil, false, :extension => extension) do |tmp|
    if format == 'excel'
      CombinationIndex.export_excel(tsv, tmp, unmerge, expand)
      require 'base64'
      Base64.encode64(Open.read(tmp, :mode => 'rb'))
    else
      CombinationIndex.export_tsv(tsv, tmp, unmerge, expand)
      Open.read(tmp)
    end
  end
end
