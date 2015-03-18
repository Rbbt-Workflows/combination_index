
rbbt.insist_get = function(params, deferred, timeout){
  if (undefined === deferred) deferred = m.deferred()
  if (undefined === timeout) timeout = 1000
  if (timeout > 10000) timeout = 10000

  params.extract = function(xhr, xhrOptions){
    if (xhr.status == '202') throw(xhr)
    return xhr.responseText
  }

  m.request(params).then(
    function(res){
      deferred.resolve(res)
    }, 
    function(xhr){ 
      if (xhr.status == '202'){ 
        if (xhr.responseURL != params.url) params = $.extend(params, {url: xhr.responseURL, method: 'GET', data: params.data})
        if (params.data !== undefined && params.data['_update'] !== undefined) params.data['_update'] = undefined
        setTimeout(function(){ rbbt.insist_get(params, deferred,timeout*1.5) }, timeout)
      }else{ deferred.reject(new Error(xhr.split(" ")[0])) }
    }
  )

  return deferred.promise
}

rbbt.job = function(workflow, task, inputs){
  var url = '/' + workflow + '/' + task

  var data = new FormData()
  data.append("_format", 'raw')
  for (i in inputs){
    data.append(i, inputs[i])
  }

  var deferred = m.deferred()

  var params = {
    url: url, 
    method: 'POST', 
    serialize: function(data) {return data},
    data: data,
    deserialize: function(value) {return value},
  }

  return rbbt.insist_get(params, deferred)
}
