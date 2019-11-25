# Copyright:: 2017-2018 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

resource_name :hab_service

property :service_name, String, name_property: true
property :loaded, [true, false], default: false, desired_state: true
property :running, [true, false], default: false, desired_state: true

# hab svc options which get included based on the action of the resource
property :strategy, [Symbol, String], equal_to: [:none, 'none', :'at-once', 'at-once', :rolling, 'rolling'], default: :none
property :topology, [Symbol, String], equal_to: [:standalone, 'standalone', :leader, 'leader'], default: :standalone
property :bldr_url, String, default: 'https://bldr.habitat.sh'
property :channel, [Symbol, String], default: :stable
property :bind, [String, Array], coerce: proc { |b| b.is_a?(String) ? [b] : b }, default: []
property :binding_mode, [Symbol, String], equal_to: [:strict, 'strict', :relaxed, 'relaxed'], default: :strict
property :service_group, String, default: 'default'
property :shutdown_timeout, Integer, default: 8
property :health_check_interval, Integer, default: 30
property :remote_sup, String, default: '127.0.0.1:9632', desired_state: false
# Http port needed for querying/comparing current config value
property :remote_sup_http, String, default: '127.0.0.1:9631', desired_state: false

load_current_value do
  service_details = get_service_details(service_name)

  running service_up?(service_details)
  loaded service_loaded?(service_details)

  if loaded
    strategy get_update_strategy(service_details)
    topology get_topology(service_details)
    bldr_url get_builder_url(service_details)
    channel get_channel(service_details)
    bind get_binds(service_details)
    binding_mode get_binding_mode(service_details)
    service_group get_service_group(service_details)
    shutdown_timeout get_shutdown_timeout(service_details)
    health_check_interval get_health_check_interval(service_details)
  end

  Chef::Log.debug("service #{service_name} running state: #{running}")
  Chef::Log.debug("service #{service_name} loaded state: #{loaded}")
  Chef::Log.debug("service #{service_name} strategy: #{strategy}")
  Chef::Log.debug("service #{service_name} topology: #{topology}")
  Chef::Log.debug("service #{service_name} builder url: #{bldr_url}")
  Chef::Log.debug("service #{service_name} channel: #{channel}")
  Chef::Log.debug("service #{service_name} binds: #{bind}")
  Chef::Log.debug("service #{service_name} binding mode: #{binding_mode}")
  Chef::Log.debug("service #{service_name} service group: #{service_group}")
  Chef::Log.debug("service #{service_name} shutdown timeout: #{shutdown_timeout}")
  Chef::Log.debug("service #{service_name} health check interval: #{health_check_interval}")
end

# This method is defined here otherwise it isn't usable in the
# `load_current_value` method.
#
# It performs a check with TCPSocket to ensure that the HTTP API is
# available first. If it cannot connect, it assumes that the service
# is not running. It then attempts to reach the `/services` path of
# the API to get a list of services. If this fails for some reason,
# then it assumes the service is not running.
#
# Finally, it walks the services returned by the API to look for the
# service we're configuring. If it is "Up", then we know the service
# is running and fully operational according to Habitat. This is
# wrapped in a begin/rescue block because if the service isn't
# present and `sup_for_service_name` will be nil and we will get a
# NoMethodError.
#
def get_service_details(svc_name)
  http_uri = "http://#{remote_sup_http}"

  begin
    TCPSocket.new(URI(http_uri).host, URI(http_uri).port).close
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    Chef::Log.debug("Could not connect to #{http_uri} to retrieve status for #{service_name}")
    return false
  end

  begin
    svcs = Chef::HTTP::SimpleJSON.new(http_uri).get('/services')
  rescue
    Chef::Log.debug("Could not connect to #{http_uri}/services to retrieve status for #{service_name}")
    return false
  end

  origin, name, _version, _release = svc_name.split('/')
  sanitized_name = [origin, name].join('/')
  svcs.find do |s|
    [s['pkg']['origin'], s['pkg']['name']].join('/') == sanitized_name
  end
end

def service_up?(service_details)
  begin
    service_details['process']['state'] == 'up'
  rescue
    Chef::Log.debug("#{service_name} not found on the Habitat supervisor")
    false
  end
end

def service_loaded?(service_details)
  if service_details
    true
  else
    false
  end
end

def get_update_strategy(service_details)
  begin
    service_details['update_strategy']
  rescue
    Chef::Log.debug("Update Strategy for #{service_name} not found on Supervisor API")
    'none'
  end
end

def get_topology(service_details)
  begin
    service_details['topology']
  rescue
    Chef::Log.debug("Topology for #{service_name} not found on Supervisor API")
    'standalone'
  end
end

def get_builder_url(service_details)
  begin
    service_details['bldr_url']
  rescue
    Chef::Log.debug("Builder URL for #{service_name} not found on Supervisor API")
    'https://bldr.habitat.sh'
  end
end

def get_channel(service_details)
  begin
    service_details['channel']
  rescue
    Chef::Log.debug("Channel for #{service_name} not found on Supervisor API")
    'stable'
  end
end

def get_binds(service_details)
  begin
    service_details['binds']
  rescue
    Chef::Log.debug("Update Strategy for #{service_name} not found on Supervisor API")
    []
  end
end

def get_binding_mode(service_details)
  begin
    service_details['binding_mode']
  rescue
    Chef::Log.debug("Binding mode for #{service_name} not found on Supervisor API")
    'strict'
  end
end

def get_service_group(service_details)
  begin
    service_details['service_group'].split('.').last
  rescue
    Chef::Log.debug("Service Group for #{service_name} not found on Supervisor API")
    'default'
  end
end

def get_shutdown_timeout(service_details)
  begin
    service_details['pkg']['shutdown_timeout']
  rescue
    Chef::Log.debug("Shutdown Timeout for #{service_name} not found on Supervisor API")
    8
  end
end

def get_health_check_interval(service_details)
  begin
    service_details['health_check_interval']['secs']
  rescue
    Chef::Log.debug("Health Check Interval for #{service_name} not found on Supervisor API")
    30
  end
end

action :load do
  reload = false

  converge_if_changed :strategy do reload = true end
  converge_if_changed :topology do reload = true end
  converge_if_changed :bldr_url do reload = true end
  converge_if_changed :channel do reload = true end
  converge_if_changed :bind do reload = true end
  converge_if_changed :binding_mode do reload = true end
  converge_if_changed :service_group do reload = true end
  converge_if_changed :shutdown_timeout do reload = true end
  converge_if_changed :health_check_interval do reload = true end

  options = svc_options
  if reload
    Chef::Log.debug("Reloading #{current_resource.service_name} using --force due to parameter change")
    options << "--force"
  end

  execute "hab svc load #{new_resource.service_name} #{options.join(' ')}" unless current_resource.loaded && !reload
end

action :unload do
  execute "hab svc unload #{new_resource.service_name} #{svc_options.join(' ')}" if current_resource.loaded
end

action :start do
  unless current_resource.loaded
    Chef::Log.fatal("No service named #{new_resource.service_name} is loaded on the Habitat supervisor")
    raise "No service named #{new_resource.service_name} is loaded on the Habitat supervisor"
  end

  execute "hab svc start #{new_resource.service_name} #{svc_options.join(' ')}" unless current_resource.running
end

action :stop do
  unless current_resource.loaded
    Chef::Log.fatal("No service named #{new_resource.service_name} is loaded on the Habitat supervisor")
    raise "No service named #{new_resource.service_name} is loaded on the Habitat supervisor"
  end

  execute "hab svc stop #{new_resource.service_name} #{svc_options.join(' ')}" if current_resource.running
end

action :restart do
  action_unload
  ruby_block do
    block do
      service_details = get_service_details(new_resource.service_name)
      raise "#{new_resource.service_name} still started" if service_up?(service_details)
    end
    retries get_shutdown_timeout(new_resource.service_name) + 1
    retry_delay 1
    action :nothing
    subscribes :run, 'action_unload[stop as part of reload]', :immediately
  end
  action_load
end

action :reload do
  action_unload
  ruby_block do
    block do
      service_details = get_service_details(new_resource.service_name)
      raise "#{new_resource.service_name} still loaded" if service_loaded?(service_details)
    end
    retries get_shutdown_timeout(new_resource.service_name) + 1
    retry_delay 1
    action :nothing
    subscribes :run, 'action_unload[unload as part of reload]', :immediately
  end
  action_load
end

action_class do
  def svc_options
    opts = []

    # certain options are only valid for specific `hab svc` subcommands.
    case action
    when :load
      opts.push(*new_resource.bind.map { |b| "--bind #{b}" }) if new_resource.bind
      opts << "--binding-mode #{new_resource.binding_mode}"
      opts << "--url #{new_resource.bldr_url}" if new_resource.bldr_url
      opts << "--channel #{new_resource.channel}" if new_resource.channel
      opts << "--group #{new_resource.service_group}" if new_resource.service_group
      opts << "--strategy #{new_resource.strategy}" if new_resource.strategy
      opts << "--topology #{new_resource.topology}" if new_resource.topology
      opts << "--health-check-interval #{new_resource.health_check_interval}" if new_resource.health_check_interval
      opts << "--shutdown-timeout #{new_resource.shutdown_timeout}" if new_resource.shutdown_timeout
    when :unload, :stop
      opts << "--shutdown-timeout #{new_resource.shutdown_timeout}" if new_resource.shutdown_timeout
    end

    opts << "--remote-sup #{new_resource.remote_sup}" if new_resource.remote_sup

    opts.map(&:split).flatten.compact
  end
end
