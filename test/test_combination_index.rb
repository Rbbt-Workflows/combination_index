$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'test/unit'
require 'combination_index'

class TestCombinationIndex < Test::Unit::TestCase
  def test_combination_index
    doses = [0.2, 0.4, 0.8, 1.6, 3.2,6.4,12.8]
    responses = [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6]
    median_point = 0.8
    model_type = :least_squares
    TmpFile.with_file do |model_file|
      fit = CombinationIndex.fit_m_dm(doses, responses, model_file, median_point, model_type)
      iii fit
    end
      
    assert true
  end
end

