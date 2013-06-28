require "cf-registrar"
require "cf_message_bus/mock_message_bus"

module CfRegistrar
  describe Config do
    after do
      [:logger, :message_bus_uri, :type, :host, :port, :username, :password, :uri, :tags, :uuid, :index].each do |field|
        CfRegistrar::Config.send(:"#{field}=", nil) ### WHY are we even doing this configure block like this. why not just a new
      end
    end
    subject { CfRegistrar::Config.configure(config) }

    describe ".configure" do
      let(:config) { {"mbus" => "m", "host" => "h", "port" => "p", "uri" => "u", "tags" => "t", "index" => 1} }

      its(:logger) { should be_a Steno::Logger }
      its(:message_bus_uri) { should eq "m" }
      its(:host) { should eq "h" }
      its(:port) { should eq "p" }
      its(:uri) { should eq "u" }
      its(:tags) { should eq "t" }
      its(:index) { should eq 1 }

      context "when the index is not provided" do
        let(:config) { {"mbus" => "m", "host" => "h", "port" => "p", "uri" => "u", "tags" => "tag"} }

        its(:index) { should eq 0 }
      end

      context "when no varz has been provided" do
        let(:config) { {} }

        its(:username) { should be_nil }
        its(:password) { should be_nil }
        its(:type) { should be_nil }
        its(:uuid) { should be_nil }
      end

      context "when there is a varz provided" do
        let(:config) { {"varz" => {"username" => "user", "password" => "pass", "type" => "foo", "uuid" => "123"}} }

        its(:username) { should eq "user" }
        its(:password) { should eq "pass" }
        its(:type) { should eq "foo" }
        its(:uuid) { should eq "123" }

        context "and a uuid is not provided" do
          let(:config) { {"varz" => {"username" => "user", "password" => "pass", "type" => "foo"}} }

          its(:uuid) { should_not be_nil }
        end
      end
    end
  end

  describe Registrar do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:bus_uri) { "a message bus uri" }
    let(:logger) { double(:logger, info: nil, error: nil, debug: nil) }
    let(:config) do
      {
        "mbus" => bus_uri,
        "host" => "registrar.host",
        "port" => 98765,
        "uri" => "fancyuri",
        "tags" => "taggy goodness",
        "varz" => {}
      }
    end

    before do
      EM.stub(:cancel_timer)
      Config.configure(config)
      Config.stub(:logger).and_return(logger)
      CfMessageBus::MessageBus.stub(:new) { message_bus }
    end

    describe "#register_with_router" do
      let(:registration_message) do
        {
          host: config["host"],
          port: config["port"],
          uris: Array(config["uri"]),
          tags: config["tags"]
        }
      end

      it "creates the message bus correctly with logger" do
        CfMessageBus::MessageBus.should_receive(:new).with(uri: bus_uri, logger: logger)
        subject.register_with_router
      end

      it "registers routes immediately" do
        subject.register_with_router
        expect(message_bus).to have_published_with_message("router.register", registration_message)
      end

      it "registers upon a router.start message" do
        EM.should_receive(:add_periodic_timer).with(33)

        subject.register_with_router

        message_bus.clear_published_messages

        message_bus.publish("router.start", {minimumRegisterIntervalInSeconds: 33})

        expect(message_bus).to have_published_with_message("router.register", registration_message)
      end

      it "greets the router" do
        EM.should_receive(:add_periodic_timer).with(33)

        subject.register_with_router

        message_bus.clear_published_messages

        message_bus.respond_to_request("router.greet", {minimumRegisterIntervalInSeconds: 33})
      end

      it "periodically registers with the router" do
        EM.should_receive(:add_periodic_timer).with(33).and_return(:periodic_timer)
        subject.register_with_router
        message_bus.publish("router.start", {minimumRegisterIntervalInSeconds: 33})
      end

      it "clears an existing timer when registering a new one" do
        subject.register_with_router

        EM.should_receive(:add_periodic_timer).with(33).and_return(:periodic_timer)
        message_bus.publish("router.start", {minimumRegisterIntervalInSeconds: 33})

        EM.should_receive(:cancel_timer).with(:periodic_timer)
        EM.should_receive(:add_periodic_timer).with(24)
        message_bus.publish("router.start", {minimumRegisterIntervalInSeconds: 24})
      end

      context "when there is no timer interval returned" do
        it "does not set up a timer" do
          subject.register_with_router

          EM.should_not_receive(:add_periodic_timer)
          message_bus.publish("router.start", {})
        end
      end
    end
  end
end
