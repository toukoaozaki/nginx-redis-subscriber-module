require File.expand_path('base_test_case', File.dirname(__FILE__))

class TestSubscriberLongPolling < Test::Unit::TestCase
  include BaseTestCase

  def global_configuration
    @ping_message_interval = nil
    @header_template = nil
    @footer_template = nil
    @message_template = nil
    @subscriber_mode = 'long-polling'
  end

  def test_disconnect_after_receive_a_message_when_longpolling_is_on
    headers = {'accept' => 'application/json'}
    channel = 'ch_test_disconnect_after_receive_a_message_when_longpolling_is_on'
    body = 'body'
    response = ""

    EventMachine.run {
      sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
      sub_1.stream { |chunk|
        response += chunk
      }
      sub_1.callback { |chunk|
        assert_equal("#{body}\r\n", response, "Wrong message")

        headers.merge!({'If-Modified-Since' => sub_1.response_header['LAST_MODIFIED'], 'If-None-Match' => sub_1.response_header['ETAG']})
        response = ""
        sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_2.stream { |chunk|
          response += chunk
        }
        sub_2.callback { |chunk|
          assert_equal("#{body} 1\r\n", response, "Wrong message")
          EventMachine.stop
        }

        publish_message_inline(channel, {'accept' => 'text/html'}, body + " 1")
      }

      publish_message_inline(channel, {'accept' => 'text/html'}, body)

      add_test_timeout
    }
  end

  def test_disconnect_after_receive_old_messages_by_backtrack_when_longpolling_is_on
    channel = 'ch_test_disconnect_after_receive_old_messages_by_backtrack_when_longpolling_is_on'

    response = ''

    EventMachine.run {
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 1')
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 2')
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 3')
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 4')

      sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + '.b2').get
      sub.stream { | chunk |
        response += chunk
      }
      sub.callback { |chunk|
        assert_equal("msg 3\r\nmsg 4\r\n", response, "The published message was not received correctly")

        response = ''
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => {'If-Modified-Since' => sub.response_header['LAST_MODIFIED'], 'If-None-Match' => sub.response_header['ETAG']}
        sub_1.stream { | chunk |
          response += chunk
        }
        sub_1.callback { |chunk|
          assert_equal("msg 5\r\n", response, "The published message was not received correctly")

          EventMachine.stop
        }

        publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 5')
      }

      add_test_timeout
    }
  end

  def test_disconnect_after_receive_old_messages_by_last_event_id_when_longpolling_is_on
    channel = 'ch_test_disconnect_after_receive_old_messages_by_last_event_id_when_longpolling_is_on'

    response = ''

    EventMachine.run {
      publish_message_inline(channel, {'accept' => 'text/html', 'Event-Id' => 'event 1' }, 'msg 1')
      publish_message_inline(channel, {'accept' => 'text/html', 'Event-Id' => 'event 2' }, 'msg 2')
      publish_message_inline(channel, {'accept' => 'text/html' }, 'msg 3')
      publish_message_inline(channel, {'accept' => 'text/html', 'Event-Id' => 'event 3' }, 'msg 4')

      sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => {'Last-Event-Id' => 'event 2' }
      sub.stream { | chunk |
        response += chunk
      }
      sub.callback { |chunk|
        assert_equal("msg 3\r\nmsg 4\r\n", response, "The published message was not received correctly")
        EventMachine.stop
      }

      add_test_timeout
    }
  end

  def test_receive_old_messages_from_different_channels
    headers = {'accept' => 'application/json'}
    channel_1 = 'ch_test_receive_old_messages_from_different_channels_1'
    channel_2 = 'ch_test_receive_old_messages_from_different_channels_2'
    body = 'body'
    response = ''

    EventMachine.run {
      publish_message_inline(channel_1, {'accept' => 'text/html'}, body + "_1")
      publish_message_inline(channel_2, {'accept' => 'text/html'}, body + "_2")

      sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2.to_s + '/' + channel_1.to_s).get :head => headers, :timeout => 30
      sub_1.callback {
        assert_equal(200, sub_1.response_header.status, "Wrong status")
        assert_not_equal("", sub_1.response_header['LAST_MODIFIED'].to_s, "Wrong header")
        assert_not_equal("", sub_1.response_header['ETAG'].to_s, "Wrong header")
        assert_equal("#{body}_2\r\n#{body}_1\r\n", sub_1.response, "The published message was not received correctly")

        headers.merge!({'If-Modified-Since' => sub_1.response_header['LAST_MODIFIED'], 'If-None-Match' => sub_1.response_header['ETAG']})
        sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2.to_s + '/' + channel_1.to_s).get :head => headers, :timeout => 30
        sub_2.callback {
          assert_equal(200, sub_2.response_header.status, "Wrong status")
          assert_not_equal(sub_1.response_header['LAST_MODIFIED'], sub_2.response_header['LAST_MODIFIED'].to_s, "Wrong header")
          assert_equal("0", sub_2.response_header['ETAG'].to_s, "Wrong header")
          assert_equal("#{body}1_1\r\n", sub_2.response, "The published message was not received correctly")

          headers.merge!({'If-Modified-Since' => sub_2.response_header['LAST_MODIFIED'], 'If-None-Match' => sub_2.response_header['ETAG']})
          sub_3 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2.to_s + '/' + channel_1.to_s).get :head => headers, :timeout => 30
          sub_3.callback {
            assert_equal(200, sub_3.response_header.status, "Wrong status")
            assert_not_equal(sub_2.response_header['LAST_MODIFIED'], sub_3.response_header['LAST_MODIFIED'].to_s, "Wrong header")
            assert_equal("0", sub_3.response_header['ETAG'].to_s, "Wrong header")
            assert_equal("#{body}1_2\r\n", sub_3.response, "The published message was not received correctly")

            EventMachine.stop
          }

          sleep (1) # to publish the second message in a different second from the first
          publish_message_inline(channel_2, {'accept' => 'text/html'}, body + "1_2")
        }

        sleep (1) # to publish the second message in a different second from the first
        publish_message_inline(channel_1, {'accept' => 'text/html'}, body + "1_1")
      }

      add_test_timeout
    }
  end

  def config_test_disconnect_after_receive_a_message_when_has_header_mode_longpolling
    @subscriber_mode = nil
  end

  def test_disconnect_after_receive_a_message_when_has_header_mode_longpolling
    headers = {'accept' => 'application/json', 'X-Nginx-PushStream-Mode' => 'long-polling'}
    channel = 'ch_test_disconnect_after_receive_a_message_when_has_header_mode_longpolling'
    body = 'body'
    response = ""

    EventMachine.run {
      sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
      sub_1.stream { |chunk|
        response += chunk
      }
      sub_1.callback { |chunk|
        assert_equal("#{body}\r\n", response, "Wrong message")

        headers.merge!({'If-Modified-Since' => sub_1.response_header['LAST_MODIFIED'], 'If-None-Match' => sub_1.response_header['ETAG']})
        response = ""
        sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_2.stream { |chunk|
          response += chunk
        }
        sub_2.callback { |chunk|
          assert_equal("#{body} 1\r\n", response, "Wrong message")
          EventMachine.stop
        }

        publish_message_inline(channel, {'accept' => 'text/html'}, body + " 1")
      }

      publish_message_inline(channel, {'accept' => 'text/html'}, body)

      add_test_timeout
    }
  end

  def config_test_disconnect_after_receive_old_messages_by_backtrack_when_has_header_mode_longpolling
    @subscriber_mode = nil
  end

  def test_disconnect_after_receive_old_messages_by_backtrack_when_has_header_mode_longpolling
    headers = {'accept' => 'application/json', 'X-Nginx-PushStream-Mode' => 'long-polling'}
    channel = 'ch_test_disconnect_after_receive_old_messages_by_backtrack_when_has_header_mode_longpolling'

    response = ''

    EventMachine.run {
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 1')
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 2')
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 3')
      publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 4')

      sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + '.b2').get :head => headers
      sub.stream { | chunk |
        response += chunk
      }
      sub.callback { |chunk|
        assert_equal("msg 3\r\nmsg 4\r\n", response, "The published message was not received correctly")

        headers.merge!({'If-Modified-Since' => sub.response_header['LAST_MODIFIED'], 'If-None-Match' => sub.response_header['ETAG']})
        response = ''
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers
        sub_1.stream { | chunk |
          response += chunk
        }
        sub_1.callback { |chunk|
          assert_equal("msg 5\r\n", response, "The published message was not received correctly")

          EventMachine.stop
        }

        publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 5')
      }

      add_test_timeout
    }
  end

  def config_test_disconnect_after_receive_old_messages_by_last_event_id_when_has_header_mode_longpolling
    @subscriber_mode = nil
  end

  def test_disconnect_after_receive_old_messages_by_last_event_id_when_has_header_mode_longpolling
    channel = 'ch_test_disconnect_after_receive_old_messages_by_last_event_id_when_has_header_mode_longpolling'

    response = ''

    EventMachine.run {
      publish_message_inline(channel, {'accept' => 'text/html', 'Event-Id' => 'event 1' }, 'msg 1')
      publish_message_inline(channel, {'accept' => 'text/html', 'Event-Id' => 'event 2' }, 'msg 2')
      publish_message_inline(channel, {'accept' => 'text/html' }, 'msg 3')
      publish_message_inline(channel, {'accept' => 'text/html', 'Event-Id' => 'event 3' }, 'msg 4')

      sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => {'Last-Event-Id' => 'event 2', 'X-Nginx-PushStream-Mode' => 'long-polling' }
      sub.stream { | chunk |
        response += chunk
      }
      sub.callback { |chunk|
        assert_equal("msg 3\r\nmsg 4\r\n", response, "The published message was not received correctly")
        EventMachine.stop
      }

      add_test_timeout
    }
  end

  def config_test_receive_old_messages_from_different_channels_when_has_header_mode_longpolling
    @subscriber_mode = nil
  end

  def test_receive_old_messages_from_different_channels_when_has_header_mode_longpolling
    headers = {'accept' => 'application/json', 'X-Nginx-PushStream-Mode' => 'long-polling'}
    channel_1 = 'ch_test_receive_old_messages_from_different_channels_when_has_header_mode_longpolling_1'
    channel_2 = 'ch_test_receive_old_messages_from_different_channels_when_has_header_mode_longpolling_2'
    body = 'body'
    response = ''

    EventMachine.run {
      publish_message_inline(channel_1, {'accept' => 'text/html'}, body + "_1")
      publish_message_inline(channel_2, {'accept' => 'text/html'}, body + "_2")

      sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2.to_s + '/' + channel_1.to_s).get :head => headers, :timeout => 30
      sub_1.callback {
        assert_equal(200, sub_1.response_header.status, "Wrong status")
        assert_not_equal("", sub_1.response_header['LAST_MODIFIED'].to_s, "Wrong header")
        assert_not_equal("", sub_1.response_header['ETAG'].to_s, "Wrong header")
        assert_equal("#{body}_2\r\n#{body}_1\r\n", sub_1.response, "The published message was not received correctly")

        headers.merge!({'If-Modified-Since' => sub_1.response_header['LAST_MODIFIED'], 'If-None-Match' => sub_1.response_header['ETAG']})
        sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2.to_s + '/' + channel_1.to_s).get :head => headers, :timeout => 30
        sub_2.callback {
          assert_equal(200, sub_2.response_header.status, "Wrong status")
          assert_not_equal(sub_1.response_header['LAST_MODIFIED'], sub_2.response_header['LAST_MODIFIED'].to_s, "Wrong header")
          assert_equal("0", sub_2.response_header['ETAG'].to_s, "Wrong header")
          assert_equal("#{body}1_1\r\n", sub_2.response, "The published message was not received correctly")

          headers.merge!({'If-Modified-Since' => sub_2.response_header['LAST_MODIFIED'], 'If-None-Match' => sub_2.response_header['ETAG']})
          sub_3 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2.to_s + '/' + channel_1.to_s).get :head => headers, :timeout => 30
          sub_3.callback {
            assert_equal(200, sub_3.response_header.status, "Wrong status")
            assert_not_equal(sub_2.response_header['LAST_MODIFIED'], sub_3.response_header['LAST_MODIFIED'].to_s, "Wrong header")
            assert_equal("0", sub_3.response_header['ETAG'].to_s, "Wrong header")
            assert_equal("#{body}1_2\r\n", sub_3.response, "The published message was not received correctly")

            EventMachine.stop
          }

          sleep (1) # to publish the second message in a different second from the first
          publish_message_inline(channel_2, {'accept' => 'text/html'}, body + "1_2")
        }

        sleep (1) # to publish the second message in a different second from the first
        publish_message_inline(channel_1, {'accept' => 'text/html'}, body + "1_1")
      }

      add_test_timeout
    }
  end
end
