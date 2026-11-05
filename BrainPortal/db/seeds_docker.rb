
#
# CBRAIN Project
#
# Copyright (C) 2008-2026
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Records for the Docker development environment (docker-compose*.yml at the
# repository root). Run by 'rake db:seed:docker', which the portal container's
# entrypoint calls at each start, after db:prepare (which runs db/seeds.rb on a
# new database) and db:sanity:check.
#
# Only missing records are created; existing ones are never modified, so a
# developer's changes (e.g. the Bourreau's settings) survive restarts.
#
# Names and paths must match docker-compose.unix.yml and
# docker-compose.slurm.yml; see docker/README.md.

admin    = User.admin
everyone = EveryoneGroup.first
raise "The admin user and the 'everyone' group must exist: run 'rake db:seed' first" unless admin && everyone

def docker_seed(klass, name, attributes) #:nodoc:
  record = klass.where(:name => name).first
  if record
    puts "Docker seed: #{klass} '#{name}' exists, left as is."
    return record
  end
  record = klass.create!(attributes.merge(:name => name))
  puts "Docker seed: #{klass} '#{name}' created."
  record
end

# The portal, created by db/seeds.rb, needs a Data Provider cache
# directory (on the portal_data volume).
portal = BrainPortal.where(:name => ENV['CBRAIN_RAILS_APP_NAME']).first
raise "No BrainPortal named '#{ENV['CBRAIN_RAILS_APP_NAME']}': run 'rake db:seed' first" unless portal
if portal.dp_cache_dir.blank?
  portal.update!(:dp_cache_dir => "/home/cbrain/data/cache")
  puts "Docker seed: BrainPortal '#{portal.name}' cache directory set."
end

# The Bourreau, in the 'bourreau' container. Its name and cluster type come
# from the compose setup: bourreau_unix (ScirUnix, tasks run in the
# container) or bourreau_slurm (ScirSlurm, login node of the emulated
# cluster, docker/slurm). Switching setups creates the other record and
# leaves this one; each has its own directories, /home/cbrain/data/<name>.
bourreau_name = ENV['CBRAIN_DOCKER_BOURREAU_NAME'].presence || 'bourreau_unix'
bourreau_cms  = ENV['CBRAIN_DOCKER_BOURREAU_CMS'].presence  || 'ScirUnix'
bourreau_desc = {
  'ScirUnix'  => "Docker development Bourreau; runs the tasks in its container",
  'ScirSlurm' => "Docker development Bourreau, login node of the emulated Slurm cluster",
}[bourreau_cms] || "Docker development Bourreau"
bourreau_dir  = "/home/cbrain/data/#{bourreau_name}"
docker_seed(Bourreau, bourreau_name,
  :description                 => bourreau_desc,
  :user_id                     => admin.id,
  :group_id                    => everyone.id,
  :online                      => true,
  :read_only                   => false,
  :ssh_control_host            => 'bourreau',
  :ssh_control_user            => 'cbrain',
  :ssh_control_port            => 22,
  :ssh_control_rails_dir       => '/cbrain/Bourreau',
  :dp_cache_dir                => "#{bourreau_dir}/cache",
  :cms_shared_dir              => "#{bourreau_dir}/work",
  :cms_class                   => bourreau_cms,
  :singularity_executable_name => 'apptainer',
  :workers_instances           => 1,
  :workers_chk_time            => 10,
  :workers_log_to              => 'combined',
  :workers_verbose             => 1,
)

# A Data Provider for the developer's files, on the Bourreau container's
# bourreau_data volume (the Bourreau entrypoint creates the directory).
docker_seed(SshDataProvider, 'bourreau_data',
  :description => "Docker development files, in the bourreau container (/home/cbrain/data/dp)",
  :user_id     => admin.id,
  :group_id    => everyone.id,
  :online      => true,
  :read_only   => false,
  :remote_host => 'bourreau',
  :remote_user => 'cbrain',
  :remote_port => 22,
  :remote_dir  => '/home/cbrain/data/dp',
)
