require "./wordnet_distances/*"

require "YAML"
require "JSON"
require "priority_queue"

# TODO: Write documentation for `WordnetDistances`
module WordnetDistances
  # TODO: Put your code here
  
  POINTER_TYPES = {
    "!"   => :antonym,
    "@"   => :hypernym,
    "@i"  => :instance_hypernym,
    "~"   => :hyponym,
    "~i"  => :instance_hyponym,
    "#m"  => :member_holonym,
    "#s"  => :substance_holonym,
    "#p"  => :part_holonym,
    "%m"  => :member_meronym,
    "%s"  => :substance_meronym,
    "%p"  => :part_meronym,
    "="   => :attribute,
    "+"   => :derivationally_related_form,
    ";c"  => :domain_of_synset_topic,
    "-c"  => :member_of_this_domain_topic,
    ";r"  => :domain_of_synset_region,
    "-r"  => :member_of_this_domain_region,
    ";u"  => :domain_of_synset_usage,
    "-u"  => :member_of_this_domain_usage,
    "*"   => :entailment,
    ">"   => :cause,
    "^"   => :also_see,
    "$"   => :verb_group,
    "&"   => :similar_to,
    "<"   => :participle_of_verb,
    "\\"  => :pertainym,
    "\\r" => :derived_from_adjective
  }

  POINTER_TYPE_NAMES = {} of String => Symbol
  POINTER_TYPES.values.map { |sym| POINTER_TYPE_NAMES[sym.to_s] = sym }

  alias StringID = Int32
  class StringMapper
    @@array = [] of String
    @@hash = {} of String => StringID

    def self.[](word)
      @@hash.fetch(word) { |word|
        index = @@array.size
        @@array << word
        @@hash[word] = index
      }
    end

    def self.read(index)
      @@array[index]
    end
  end


  class Word
    getter id
    getter lex

    def initialize(@id : StringID, @lex : UInt8)
    end

    def to_s(io)
      io << StringMapper.read @id
      io << '['
      io << @lex
      io << ']'
    end
  end


  class SynsetPointer
    getter type
    getter offset
    getter pos

    def initialize(@type : Symbol, @offset : UInt32, @pos : Char)
    end

    def to_s(io)
      io << @type << " of " << @offset << '(' << @pos << ')'
    end
  end


  alias SynsetID = Tuple(UInt32, Char)
  alias Weight = Float32
  class Synset
    getter gloss : String
    getter offset : UInt32
    getter lex_filenum : UInt8
    getter ss_type : Char
    getter words : Array(Word)
    getter pointers : Array(SynsetPointer)
    getter distances : Hash(SynsetID, Weight)

    def initialize(line : String)
      fieldstring, @gloss = line.split(" | ")
      fields = fieldstring.split
      @offset = fields.shift.to_u32
      @lex_filenum = fields.shift.to_u8
      ss_mark = fields.shift[0]
      ss_mark = 'a' if ss_mark == 's'
      @ss_type = ss_mark

      w_cnt = fields.shift.to_u8(16)
      @words = w_cnt.times.map { |i|
        word_id = StringMapper[fields.shift]
        lex_id = fields.shift.to_u8(16)
        Word.new(word_id, lex_id)
      }.to_a

      p_cnt = fields.shift.to_u16
      @pointers = p_cnt.times.map { |i|
        pointer_symbol = fields.shift
        offset = fields.shift.to_u32
        pos = fields.shift[0]
        pointer_symbol = "\\r" if pointer_symbol == "\\" && @ss_type == :adverb
        pointer_type = POINTER_TYPES[pointer_symbol]
        source_target = fields.shift
        next unless source_target == "0000"
        SynsetPointer.new(pointer_type, offset, pos)
      }.to_a.compact

      @distances = {} of SynsetID => Weight
    end

    def to_s(io)
      words.each_with_index { |word, index|
        io << '/' unless index == 0
        io << StringMapper.read word.id
      }
    end
  end


  class SynsetGraph
    def initialize
      @synsets = {} of SynsetID => Synset
    end

    def load(file)
      File.each_line(file, "us-ascii", nil, true) do |line|
        next if line[0] == ' '
        synset = Synset.new(line)
        @synsets[{synset.offset, synset.ss_type}] = synset
      end
    end

    def to_s(io)
      @synsets.each do |id, synset|
        io << id[0] << '(' << id[1] << "): "
        synset.to_s io
        io << '\n'
      end
    end

    def calculate_distance(limit, synset_id)
      synset = @synsets[synset_id]
      seen = Set{synset_id}
      queue = PriorityQueue{0_f32 => synset_id}

      until queue.empty?
        old_distance = -queue.priority
        current = @synsets[queue.pop]

        current.pointers.each do |pointer|
          distance = old_distance + WEIGHTS[pointer.type]
          next if distance > limit

          target_id = {pointer.offset, pointer.pos}
          next if seen.includes?(target_id)
          seen << target_id

          synset.distances[target_id] = distance
          queue[-distance] = target_id
        end
      end
    end

    def print_distances(synset_id)
      synset = @synsets[synset_id]
      puts synset
      synset.distances.each do |target_id, distance|
        puts "\t#{distance}\t#{@synsets[target_id]}"
      end
    end

    def calculate_distances(limit)
      @synsets.each_with_index do |(synset_id, synset), index|
        puts "#{index}\t#{synset}" if VERBOSE

        calculate_distance(limit, synset_id)
        yield synset

        # forget, to reclaim memory
        synset.distances.clear
      end
    end

    def calculate_distances_to_text_file(limit, file)
      File.open(file, "w") do |f|
        calculate_distances(limit) do |synset|
          distances = synset.distances.map { |target_id, dist| "#{target_id[0]} #{target_id[1]} #{dist}" }.join(", ")
          f.puts("#{synset.offset} #{synset.ss_type}: #{distances}")
        end
      end
    end

    def calculate_distances_to_bin_file(limit, file, index_file)
      index = Hash(Char, Hash(UInt32, Int64)).new { |h, k| h[k] = Hash(UInt32, Int64).new }
      File.open(file, "wb") do |f|
        f.write_bytes(@synsets.size)
        calculate_distances(limit) do |synset|
          f.flush
          index[synset.ss_type][synset.offset] = f.tell
          f.write_bytes(synset.offset)
          f.write_byte(synset.ss_type.ord.to_u8)
          f.write_bytes(synset.distances.size)
          synset.distances.each do |target_id, distance|
            f.write_bytes(target_id[0])
            f.write_byte(target_id[1].ord.to_u8)
            f.write_bytes(distance)
          end
        end
      end
      File.open(index_file, "wb") do |f|
        f.write_bytes(index.size)
        index.each do |pos, pos_data|
          f.write_byte(pos.ord.to_u8)
          f.write_bytes(pos_data.size)
          pos_data.each do |offset, loc|
            f.write_bytes(offset)
            f.write_bytes(loc)
          end
        end
      end
    end
  end

  CONFIG = YAML.parse(File.read("config.yaml"))
  WEIGHTS = {} of Symbol => Weight
  POINTER_TYPE_NAMES.each do |str, sym|
    WEIGHTS[sym] = CONFIG["weights"][str].as_f.to_f32
  rescue KeyError
    WEIGHTS[sym] = 1.0_f32
  end
  LIMIT = CONFIG["limit"].as_f.to_f32 rescue 1.0
  VERBOSE = CONFIG["verbose"] rescue false
  BINARY = CONFIG["verbose"] rescue false

  graph = SynsetGraph.new
  graph.load("dict/data.adj")
  graph.load("dict/data.adv")
  graph.load("dict/data.noun")
  graph.load("dict/data.verb")

  file = CONFIG["filename"] rescue "distances"
  if BINARY
    graph.calculate_distances_to_bin_file(LIMIT, "#{file}.bin", "#{file}.idx")
  else
    graph.calculate_distances_to_text_file(LIMIT, "#{file}.txt")
  end

  # puts "------------ Java the Island"
  # example_id = {8928021_u32, 'n'} # java the island
  # graph.calculate_distance(LIMIT, example_id)
  # graph.print_distances(example_id)

  # puts "------------ Java the Coffee"
  # example_id = {7945759_u32, 'n'} # java the coffee
  # graph.calculate_distance(LIMIT, example_id)
  # graph.print_distances(example_id)

  # puts "------------ Java the Language"
  # example_id = {6913829_u32, 'n'} # java the language
  # graph.calculate_distance(LIMIT, example_id)
  # graph.print_distances(example_id)
end
