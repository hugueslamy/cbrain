
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

namespace :db do
  namespace :seed do
    desc "Create the Bourreau and Data Provider records of the Docker development environment"
    task :docker => :environment do
      # CBRAIN skips its boot checks for db: tasks, but validating a cache
      # directory needs CBRAIN::SelfRemoteResourceId, set by this one
      CbrainSystemChecks.check([:a002_ensure_Rails_can_find_itself])
      load "db/seeds_docker.rb"
    end
  end
end
