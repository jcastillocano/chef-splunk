#
# Cookbook Name:: splunk
# Recipe:: setup
#
# Author: Joshua Timberman <joshua@chef.io>
# Copyright (c) 2014, Chef Software, Inc <legal@chef.io>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This recipe encapsulates a completely configured "client" - a
# Universal Forwarder configured to talk to a node that is the splunk
# server (with node['splunk']['is_server'] true). The recipes can be
# used on their own composed in your own wrapper cookbook or role.

splunk_servers = if node['splunk']['splunk_servers']
                   node['splunk']['splunk_servers']
                 else
                   search( # ~FC003
                     :node,
                     "splunk_is_server:true AND chef_environment:#{node.chef_environment}"
                   ).sort! do |a, b|
                     a.name <=> b.name
                   end
                 end

servers_hash = []
splunk_servers.each do |s|
  servers_hash.push('ipaddress' => s['ipaddress'], 'port' => s['splunk']['receiver_port'])
end

node.set['splunk']['output_groups']['default']['servers'] = servers_hash

# ensure that the splunk service resource is available without cloning
# the resource (CHEF-3694). this is so the later notification works,
# especially when using chefspec to run this cookbook's specs.
begin
  resources('service[splunk]')
rescue Chef::Exceptions::ResourceNotFound
  service 'splunk'
end

base_config_dir = "#{splunk_dir}/etc/#{node['splunk']['splunk_config_path']}"
directory base_config_dir do
  recursive true
  owner node['splunk']['user']['username']
  group node['splunk']['user']['username']
end

template "#{base_config_dir}/outputs.conf" do
  source 'outputs.conf.erb'
  mode 0644
  variables outputs: node['splunk']['output_groups']
  notifies :restart, 'service[splunk]'
end

template "#{base_config_dir}/inputs.conf" do
  source 'inputs.conf.erb'
  mode 0644
  variables inputs_conf: node['splunk']['inputs_conf']
  notifies :restart, 'service[splunk]'
  not_if { node['splunk']['inputs_conf'].nil? || node['splunk']['inputs_conf']['host'].empty? }
  only_if { !node['splunk']['inputs_conf']['inputs'].nil? && !node['splunk']['inputs_conf']['inputs'].empty? }
end

template "#{splunk_dir}/etc/apps/SplunkUniversalForwarder/default/limits.conf" do
  source 'limits.conf.erb'
  mode 0644
  variables ratelimit_kbps: node['splunk']['ratelimit_kilobytessec']
  notifies :restart, 'service[splunk]'
end

include_recipe 'chef-splunk::service'
include_recipe 'chef-splunk::setup_auth' if node['splunk']['setup_auth']
