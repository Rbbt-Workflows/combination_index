require 'rbbt/util/R/plot'
require 'prawn'
require 'prawn-svg'

require 'tasks/CI/fit'
require 'tasks/CI/ci'
require 'tasks/CI/bliss'
require 'tasks/CI/hsa'

module CombinationIndex
 
  export_asynchronous :fit, :ci, :bliss, :hsa, :report, :report_bliss, :report_hsa
end
