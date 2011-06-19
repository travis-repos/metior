# This code is free software; you can redistribute it and/or modify it under
# the terms of the new BSD License.
#
# Copyright (c) 2011, Sebastian Staudt

require 'octokit'

require 'metior/github'
require 'metior/github/commit'
require 'metior/repository'

module Metior

  module GitHub

    # Represents a GitHub source code repository
    #
    # @author Sebastian Staudt
    class Repository < Metior::Repository

      include Metior::GitHub

      # @return [String] The project name of the repository
      attr_reader :project

      # @return [String] The GitHub username of the repository's owner
      attr_reader :user

      # Creates a new GitHub repository based on the given user and project
      # names
      #
      # @param [String] user The GitHub username of repository's owner
      # @param [String] project The name of the project
      def initialize(user, project = nil)
        user, project = user.split('/') if user.include? '/'

        super "#{user}/#{project}"

        @project = project
        @user    = user
      end

      private

      def id_for_ref(ref)
        return ref if ref.match /[0-9a-f]{40}/
        commit = Octokit.get("api/v2/json/commits/show/#{@path}/#{ref}")['commit']
        commit.id
      end

      # This method uses Octokit to load all commits from the given commit
      # range
      #
      # @note GitHub API is currently limited to 60 calls a minute, so you
      #       won't be able to query branches with more than 2100 commits
      #       (35 commits per call).
      # @param [String, Range] range The range of commits for which the commits
      #        should be loaded. This may be given as a string
      #        (`'master..development'`), a range (`'master'..'development'`)
      #        or as a single ref (`'master'`). A single ref name means all
      #        commits reachable from that ref.
      # @return [Hashie::Rash, nil] The base commit of the requested range or
      #         `nil` if the the range starts at the beginning of the history
      # @return [Array<Hashie::Rash>] All commits in the given commit range
      # @see Octokit::Commits#commits
      def load_commits(range)
        base_commit = nil
        commits = []
        page = 1
        begin
          loop do
            new_commits = Octokit.commits(@path, range.last, :page => page)
            base_commit_index = new_commits.find_index do |commit|
              commit.id == range.first
            end
            unless base_commit_index.nil?
              commits += new_commits[0..base_commit_index-1]
              base_commit = new_commits[base_commit_index]
              break
            end
            commits += new_commits
            page += 1
          end
        rescue Octokit::NotFound, Faraday::Error::ResourceNotFound
        end

        [base_commit, commits]
      end

    end

  end

end
