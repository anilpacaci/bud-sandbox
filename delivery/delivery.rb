require 'rubygems'
require 'bud'

module DeliveryProtocol
  def state
    super
    interface input, :pipe_in, [:dst, :src, :ident] => [:payload]
    interface output, :pipe_sent, [:dst, :src, :ident] => [:payload]
  end
end

module BestEffortDelivery
  include DeliveryProtocol
  include Anise
  annotator :declare

  def state
    super
    #channel :pipe_chan, [:@dst, :src, :ident] => [:payload]
    channel :pipe_chan, [:dst, :src, :ident] => [:payload]
  end

  declare
    def snd
      pipe_chan <~ pipe_in
    end

  declare
    def done
      # vacuous ackuous.  override me!
      pipe_sent <= pipe_in
    end
end
