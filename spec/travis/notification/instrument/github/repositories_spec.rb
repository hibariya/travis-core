require 'spec_helper'

describe Travis::Notification::Instrument::Github::Repositories do
  include Travis::Testing::Stubs

  let(:repos)     { Travis::Github::Repositories.new(user) }
  let(:publisher) { Travis::Notification::Publisher::Memory.new }
  let(:event)     { publisher.events[1] }

  before :each do
    Travis::Notification.publishers.replace([publisher])
    GH.stubs(:[]).returns([])
    repos.fetch
  end

  it 'publishes a payload' do
    event.should == {
      :message => "travis.github.repositories.fetch:completed",
      :payload => { :result => [], :msg=>"Travis::Github::Repositories#fetch for #<User id=1 login=\"svenfuchs\">" },
      :uuid => Travis.uuid
    }
  end
end

