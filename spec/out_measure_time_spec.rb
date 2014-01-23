# encoding: UTF-8
require_relative 'spec_helper'

class Fluent::Test::OutputTestDriver
  def emit_with_tag(record, time=Time.now, tag = nil)
    @tag = tag if tag
    emit(record, time)
  end
end

class Hash
  def delete!(key)
    self.tap {|h| h.delete(key) }
  end
end

describe Fluent::MeasureTimeOutput do
  before { Fluent::Test.setup }
  CONFIG = %[
    tag tag
    interval 120
    each message
    <store>
      type stdout
    </store>
  ]
  let(:tag) { 'syslog.host1' }
  let(:driver) { Fluent::Test::OutputTestDriver.new(Fluent::MeasureTimeOutput, tag).configure(config) }

  describe 'test configure' do
    describe 'bad configuration' do
      context 'invalid each' do
        let(:config) { CONFIG + %[each foobar] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end
    end

    describe 'good configuration' do
      subject { driver.instance }

      context "check default" do
        let(:config) { %[] }
        its(:tag) { should == 'measure_time' }
        its(:interval) { should == 60 }
        its(:each) { should == :es }
      end

      context "check config" do
        let(:config) { CONFIG }
        its(:tag) { should == 'tag' }
        its(:interval) { should == 120 }
        its(:each) { should == :message }
      end
    end
  end

  describe 'test emit' do
    let(:time) { Time.now.to_i }
    let(:messages) do
      [
        "2013/01/13T07:02:11.124202 INFO GET /ping",
        "2013/01/13T07:02:13.232645 WARN POST /auth",
        "2013/01/13T07:02:21.542145 WARN GET /favicon.ico",
        "2013/01/13T07:02:43.632145 WARN POST /login",
      ]
    end

    context 'each message' do
      let(:config) { CONFIG + %[each message]}
      before do
        Fluent::Engine.stub(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        driver.instance.elapsed.size.should == 4
      }
    end

    context 'each es' do
      let(:config) { CONFIG + %[each es]}
      before do
        Fluent::Engine.stub(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        driver.instance.elapsed.size.should == 4
      }
    end
  end
end
