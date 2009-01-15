require 'rubygems'
require 'sinatra'
require 'sinatra/test/unit'


# Require application file
require '../marley/vector'

class VectorTest < Test::Unit::TestCase
  
  def test_unit
    v = Marley::Vector.from_string("<pre> hi there, it's snowing </pre>")
    assert_equal 1.0, v.stems.inject(0){|s,x| s+= v.unit(x) * v.unit(x)}
  end

  def test_inner_product
    v = Marley::Vector.from_string("<pre> hi there, it's snowing </pre>")
    u = Marley::Vector.from_string("<pre> hi there, it's snowing </pre>")
    assert_equal 1.0, v * u
  end

end