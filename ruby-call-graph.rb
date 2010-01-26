#!/usr/bin/ruby

require 'rubygems'
require 'graphviz'
require 'optparse'

class CallGraph
  private
  class Call
    attr_reader :file
    attr_reader :method

    def initialize(file, method)
      @file = file
      @method = method
    end

    def to_s
      (file+"::#"+method)
    end

    def eql?(rhs)
      rhs.is_a?(Call) && to_s == rhs.to_s
    end

    def hash()
      to_s.hash
    end
  end

  attr_accessor :call_graph
  attr_accessor :rev_call_graph
  attr_accessor :call_set
  attr_accessor :graph
  attr_accessor :nodes

  public
  def initialize
    @call_graph = Hash.new {|h, k| h[k] = Hash.new(0) }
    @rev_call_graph = Hash.new {|h, k| h[k] = Hash.new(0) }
    @call_set = Hash.new(0)
    @graph = GraphViz.new(:G, :type => :digraph)
    @nodes = {}
  end

  def parse_stack_trace(handle)
    stack = []
    handle.each do |line|
      line.chomp!

      case line
      when /\/(\w+?)\.\w+:\d+:in `(.+)'$/ then
        file = $1
        call = $2

        call = Call.new(file, call)
        stack.push(call)
        call_set[call] += 1
      when /^--$/ then
        stack[0..-2].zip(stack[1..-1]).each do |from, to|
          next if from.eql?(to)
          call_graph[from][to] += 1
          rev_call_graph[to][from] += 1
        end unless stack.empty?
        stack.clear
      end
    end
  end

  def generate_nodes(min_font_size, max_font_size, threshold)
    max_block = lambda { |max, n| n > max ? n : max }
    max_count = call_set.values.inject(0, &max_block)
    call_set.each_pair do |call, count|
      max_edge_size = rev_call_graph[call].values.inject(call_graph[call].values.inject(0, &max_block), &max_block)
      font_size = max_font_size * count/max_count
      nodes[call] = graph.add_node(call.to_s,
                                   :fontsize => font_size > min_font_size ? font_size : min_font_size ) if count >= threshold and max_edge_size >= threshold
    end
  end

  def generate_edges(threshold)
    call_graph.each_pair do |from, to_hash|
      to_hash.each_pair do |to, count|
        from_node = nodes[from]
        to_node = nodes[to]
        next if from_node.nil? or to_node.nil?
        graph.add_edge(from_node, to_node, :label => "#{count}") if count >= threshold
      end
    end
  end

  def output(output)
    graph.output(:png => output)
  end

  def self.parse_arguments
    args = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: ruby-call-graph.rb -i INPUT -o OUTPUT [-t THRESHOLD]"

      opts.on("-i", "--input INPUT", "Input stack trace (- for stdin)") do |optarg|
        args[:input] = optarg
      end

      opts.on("-o", "--output OUTPUT", "Output filename") do |optarg|
        args[:output] = optarg
      end

      opts.on("-t", "--threshold THRESHOLD", "Edge/Node Count Threshold. Defaults to 100") do |optarg|
        args[:threshold] = optarg.to_i
      end

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

    end.parse!

    if args[:input].nil?
      puts "-i/--input required."
      exit
    end

    if args[:output].nil?
      puts "-o/--output required."
      exit
    end

   args[:threshold] = 100 if args[:threshold].nil?
   args

  end
end

options = CallGraph.parse_arguments()

cg = CallGraph.new()

begin
  inhandle = options[:input] == "-" ? STDIN : File.new(options[:input], "r")
  cg.parse_stack_trace(inhandle)
  cg.generate_nodes(12, 100, options[:threshold])
  cg.generate_edges(options[:threshold])
  cg.output(options[:output])
ensure
  inhandle.close
end
