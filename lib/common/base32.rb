# frozen_string_literal: true

module Base32

  class Chunk
    def initialize(bytes)
      @table = "abcdefghijklmnopqrstuvwxyz234567"
      @bytes = bytes
    end

    def decode
      bytes = @bytes.take_while {|c| c != 61} # strip padding
      n = (bytes.length * 5.0 / 8.0).floor
      p = bytes.length < 8 ? 5 - (n * 8) % 5 : 0
      c = bytes.inject(0) {|m,o| (m << 5) + @table.index(o.chr)} >> p
      (0..n-1).to_a.reverse.collect {|i| ((c >> i * 8) & 0xff).chr} # bla
    end

    def encode
      n = (@bytes.length * 8.0 / 5.0).ceil
      p = n < 8 ? 5 - (@bytes.length * 8) % 5 : 0
      c = @bytes.inject(0) {|m,o| (m << 8) + o} << p
      [(0..n-1).to_a.reverse.collect {|i| @table[(c >> i * 5) & 0x1f].chr},
       ("=" * (8-n))]
    end
  end

  class << self
    def chunks(str, size)
      result = []
      bytes = str.bytes
      while bytes.any? do
        result << Chunk.new(bytes.take(size))
        bytes = bytes.drop(size)
      end
      result
    end

    def encode(str)
      chunks(str, 5).collect(&:encode).flatten.join.sub(/=+$/,'')
    end

    def decode(str)
      chunks(str, 8).collect(&:decode).flatten.join
    end
  end
end