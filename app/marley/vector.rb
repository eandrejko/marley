# from http://tartarus.org/~martin/PorterStemmer/ruby.txt

module Stemmable

  STEP_2_LIST = {
    'ational'=>'ate', 'tional'=>'tion', 'enci'=>'ence', 'anci'=>'ance',
    'izer'=>'ize', 'bli'=>'ble',
    'alli'=>'al', 'entli'=>'ent', 'eli'=>'e', 'ousli'=>'ous',
    'ization'=>'ize', 'ation'=>'ate',
    'ator'=>'ate', 'alism'=>'al', 'iveness'=>'ive', 'fulness'=>'ful',
    'ousness'=>'ous', 'aliti'=>'al',
    'iviti'=>'ive', 'biliti'=>'ble', 'logi'=>'log'
  } unless defined?(STEP_2_LIST)
  
  STEP_3_LIST = {
    'icate'=>'ic', 'ative'=>'', 'alize'=>'al', 'iciti'=>'ic',
    'ical'=>'ic', 'ful'=>'', 'ness'=>''
  } unless defined?(STEP_3_LIST)


  SUFFIX_1_REGEXP = /(
                    ational  |
                    tional   |
                    enci     |
                    anci     |
                    izer     |
                    bli      |
                    alli     |
                    entli    |
                    eli      |
                    ousli    |
                    ization  |
                    ation    |
                    ator     |
                    alism    |
                    iveness  |
                    fulness  |
                    ousness  |
                    aliti    |
                    iviti    |
                    biliti   |
                    logi)$/x unless defined?(SUFFIX_1_REGEXP)

  SUFFIX_2_REGEXP = /(
                      al       |
                      ance     |
                      ence     |
                      er       |
                      ic       | 
                      able     |
                      ible     |
                      ant      |
                      ement    |
                      ment     |
                      ent      |
                      ou       |
                      ism      |
                      ate      |
                      iti      |
                      ous      |
                      ive      |
                      ize)$/x unless defined?(SUFFIX_2_REGEXP)


  C = "[^aeiou]" unless defined?(C)         # consonant
  V = "[aeiouy]" unless defined?(V)         # vowel
  CC = "#{C}(?>[^aeiouy]*)" unless defined?(CC)  # consonant sequence
  VV = "#{V}(?>[aeiou]*)" unless defined?(VV)    # vowel sequence

  MGR0 = /^(#{CC})?#{VV}#{CC}/o  unless defined?(MGR0)              # [cc]vvcc... is m>0
  MEQ1 = /^(#{CC})?#{VV}#{CC}(#{VV})?$/o  unless defined?(MEQ1)       # [cc]vvcc[vv] is m=1
  MGR1 = /^(#{CC})?#{VV}#{CC}#{VV}#{CC}/o  unless defined?(MGR1)     # [cc]vvccvvcc... is m>1
  VOWEL_IN_STEM   = /^(#{CC})?#{V}/o unless defined?(VOWEL_IN_STEM)                      # vowel in stem

  #
  # Porter stemmer in Ruby.
  #
  # This is the Porter stemming algorithm, ported to Ruby from the
  # version coded up in Perl.  It's easy to follow against the rules
  # in the original paper in:
  #
  #   Porter, 1980, An algorithm for suffix stripping, Program, Vol. 14,
  #   no. 3, pp 130-137,
  #
  # See also http://www.tartarus.org/~martin/PorterStemmer
  #
  # Send comments to raypereda@hotmail.com
  #
  
  def stem_porter

    # make a copy of the given object and convert it to a string.
    w = self.dup.to_str
    
    return w if w.length < 3
    
    # now map initial y to Y so that the patterns never treat it as vowel
    w[0] = 'Y' if w[0] == ?y
    
    # Step 1a
    if w =~ /(ss|i)es$/
      w = $` + $1
    elsif w =~ /([^s])s$/ 
      w = $` + $1
    end

    # Step 1b
    if w =~ /eed$/
      w.chop! if $` =~ MGR0 
    elsif w =~ /(ed|ing)$/
      stem = $`
      if stem =~ VOWEL_IN_STEM 
        w = stem
	case w
        when /(at|bl|iz)$/             then w << "e"
        when /([^aeiouylsz])\1$/       then w.chop!
        when /^#{CC}#{V}[^aeiouwxy]$/o then w << "e"
        end
      end
    end

    if w =~ /y$/ 
      stem = $`
      w = stem + "i" if stem =~ VOWEL_IN_STEM 
    end

    # Step 2
    if w =~ SUFFIX_1_REGEXP
      stem = $`
      suffix = $1
      # print "stem= " + stem + "\n" + "suffix=" + suffix + "\n"
      if stem =~ MGR0
        w = stem + STEP_2_LIST[suffix]
      end
    end

    # Step 3
    if w =~ /(icate|ative|alize|iciti|ical|ful|ness)$/
      stem = $`
      suffix = $1
      if stem =~ MGR0
        w = stem + STEP_3_LIST[suffix]
      end
    end

    # Step 4
    if w =~ SUFFIX_2_REGEXP
      stem = $`

      if stem =~ MGR1
        w = stem
      end
    elsif w =~ /(s|t)(ion)$/
      stem = $` + $1
      if stem =~ MGR1
        w = stem
      end
    end

    #  Step 5
    if w =~ /e$/ 
      stem = $`
      if (stem =~ MGR1) ||
          (stem =~ MEQ1 && stem !~ /^#{CC}#{V}[^aeiouwxy]$/o)
        w = stem
      end
    end

    if w =~ /ll$/ && w =~ MGR1
      w.chop!
    end

    # and turn initial Y back to y
    w[0] = 'y' if w[0] == ?Y

    w
  end


  #
  # make the stem_porter the default stem method, just in case we
  # feel like having multiple stemmers available later.
  #
  alias stem stem_porter

end

class String
   include Stemmable
end



module Marley
  # a vector in a term document matrix
  class Vector
    
    def initialize
      @vec = Hash.new(0)
    end
    
    # given a string produce a vector by splitting the string into 'words' and stemming each one
    def self.from_string(str = "")
      raise "Vector.from_string called with nil" if str.nil?
      v = Vector.new
      str.split(/[\W]+/).each do |x|
        v[x.stem] ||= 0
        v[x.stem] += 1
      end
      v
    end
    
    # basic array like accessor
    def [](x)
      @vec[x]
    end
    
    def []=(x,val)
      @vec[x] = val
    end
    
    # turns vector into array
    def to_a
      @vec.to_a
    end
    
    def stems
      @vec.keys
    end
    
    # gives the coordinate of the vector normalized as a unit vector
    def unit(x)
      self[x].to_f / norm.to_f rescue 0.0
    end
    
    def norm
      Math.sqrt(to_a.inject(0){|s,x| s+= x[1]*x[1] })
    end
    
    # computes the dot product with another vector
    def *(other)
      all_stems = (self.stems + other.stems).uniq
      all_stems.inject(0){|s,x| s+= (self.unit(x) * other.unit(x)) }
    end
    
  end
end
