require 'rbbt-util'
require 'rbbt/workflow'
require 'rbbt/util/R'

require_relative 'lib/combination_index'

module CombinationIndex
  extend Workflow

end

require_relative 'lib/tasks/CI.rb'
