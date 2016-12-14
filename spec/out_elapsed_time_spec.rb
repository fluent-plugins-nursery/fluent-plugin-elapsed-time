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

describe Fluent::ElapsedTimeOutput do
  before { Fluent::Test.setup }
  CONFIG = %[
    <store>
      type stdout
    </store>
  ]
  let(:tag) { 'syslog.host1' }
  let(:driver) { Fluent::Test::OutputTestDriver.new(Fluent::ElapsedTimeOutput, tag).configure(config) }

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
        its(:tag) { should == 'elapsed' }
        its(:interval) { should == 60 }
        its(:each) { should == :es }
      end

      context "check config" do
        let(:config) { CONFIG + %[tag tag\ninterval 120\neach message]}
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
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.elapsed.size).to eq(4)
      }
    end

    context 'each es' do
      let(:config) { CONFIG + %[each es]}
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.elapsed.size).to eq(4)
      }
    end

    context 'each message with aggregate tag' do
      let(:config) { CONFIG + %[each message\naggregate tag\nadd_tag_prefix elapsed]}
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.elapsed("elapsed.#{tag}").size).to eq(4)
      }
    end

    context 'each es with aggregate tag' do
      let(:config) { CONFIG + %[each es\naggregate tag\nadd_tag_prefix elapsed]}
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.elapsed("elapsed.#{tag}").size).to eq(4)
        driver.instance.flush_emit
      }
    end

    context 'remove_tag_slice' do
      let(:config) { CONFIG + %[remove_tag_slice 0..-2\naggregate tag\nadd_tag_prefix elapsed]}
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      let(:expected_tag) { tag.split('.')[0..-2].join('.') }
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.elapsed("elapsed.#{expected_tag}").size).to eq(4)
      }
    end

    context 'zero_emit true' do
      let(:config) { CONFIG + %[zero_emit true]}
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.flush_emit["elapsed"]["num"]).to eq(4)
        expect(driver.instance.flush_emit["elapsed"]).to eq({"max" => 0, "avg" => 0, "num" => 0})
      }
    end

    context 'zero_emit false' do
      let(:config) { CONFIG }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it {
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        expect(driver.instance.flush_emit["elapsed"]["num"]).to eq(4)
        expect(driver.instance.flush_emit).to eq({})
      }
    end
  end
end
