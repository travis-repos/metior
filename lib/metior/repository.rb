# This code is free software; you can redistribute it and/or modify it under
# the terms of the new BSD License.
#
# Copyright (c) 2011, Sebastian Staudt

require 'metior/actor'

module Metior

  # This class represents a source code repository.
  #
  # @abstract It has to be subclassed to implement a repository representation
  #           for a specific VCS.
  # @author Sebastian Staudt
  class Repository

    # @return [String] The file system path of this repository
    attr_reader :path

    # Creates a new repository instance with the given file system path
    #
    # @param [String] path The file system path of the repository
    def initialize(path)
      @authors    = {}
      @commits    = {}
      @committers = {}
      @path       = path
    end

    # Returns a single VCS specific actor object from the raw data of the
    # author provided by the VCS implementation
    #
    # The author object is either created from the given raw data or retrieved
    # from the cache using the VCS specific unique identifier of the
    # author.
    #
    # @param [Object] author The raw data of the author provided by the VCS
    # @return [Actor] A object representing the author
    # @see Actor.id_for
    def author(author)
      id = self.class::Actor.id_for(author)
      @authors[id] ||= self.class::Actor.new(self, author)
    end

    # Returns all authors from the given commit range in a hash where the IDs
    # of the authors are the keys and the authors are the values
    #
    # This will call `commits(range)` if the authors for the commit range are
    # not known yet.
    #
    # @param [String, Range] range The range of commits for which the authors
    #        should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @return [Hash<String, Actor>] All authors from the given commit range
    # @see #commits
    def authors(range = self.class::DEFAULT_BRANCH)
      author_ids = commits(range).map { |commit| commit.author.id }.uniq
      Hash[@authors.select { |id, author| author_ids.include? id }]
    end
    alias_method :contributors, :authors

    # Loads all commits including their committers and authors from the given
    # commit range
    #
    # @param [String, Range] range The range of commits for which the commits
    #        should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @return [Array<Commit>] All commits from the given commit range
    def commits(range = self.class::DEFAULT_BRANCH)
      range = parse_range range
      commits = cached_commits range

      if commits.empty?
        base_commit, raw_commits = load_commits(range)
        commits = commits + build_commits(raw_commits)
        unless base_commit.nil?
          base_commit = self.class::Commit.new(self, base_commit)
          base_commit.add_child commits.last.id
          @commits[base_commit.id] = base_commit
        end
      else
        commits.pop if range.first != ''
        if range.first == ''
          unless commits.last.parents.empty?
            raw_commits = load_commits(''..commits.last.id).last
            commits += build_commits raw_commits[0..-2]
          end
        else
          if commits.first.id != range.last
            raw_commits = load_commits(commits.first.id..range.last).last
            commits = build_commits(raw_commits) + commits
          end
          unless commits.last.parents.include? range.first
            raw_commits = load_commits(range.first..commits.last.id).last
            commits += build_commits raw_commits
          end
        end
      end

      commits
    end

    # Returns a single VCS specific actor object from the raw data of the
    # committer provided by the VCS implementation
    #
    # The committer object is either created from the given raw data or
    # retrieved from the cache using the VCS specific unique identifier of the
    # committer
    #
    # @param [Object] committer The raw data of the committer provided by the
    #        VCS
    # @return [Actor] A object representing the committer
    # @see Actor.id_for
    def committer(committer)
      id = self.class::Actor.id_for(committer)
      @committers[id] ||= self.class::Actor.new(self, committer)
    end

    # Returns all committers from the given commit range in a hash where the
    # IDs of the committers are the keys and the committers are the values
    #
    # This will call `commits(range)` if the committers for the commit range
    # are not known yet.
    #
    # @param [String, Range] range The range of commits for which the
    #        committers should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @return [Hash<String, Actor>] All committers from the given commit range
    # @see #commits
    def committers(range = self.class::DEFAULT_BRANCH)
      committer_ids = commits(range).map { |commit| commit.committer.id }.uniq
      Hash[@committers.select { |id, committer| committer_ids.include? id }]
    end
    alias_method :collaborators, :committers

    # This evaluates basic statistics about the files in a given commit range.
    #
    # @example
    #  repo.file_stats
    #  => {
    #       'a_file.rb' => {
    #         :added_date => Tue Mar 29 16:13:47 +0200 2011,
    #         :deleted_date => Sun Jun 05 12:56:18 +0200 2011,
    #         :last_modified_date => Thu Apr 21 20:08:00 +0200 2011,
    #         :modifications => 9
    #       }
    #     }
    # @param [String, Range] range The range of commits for which the file
    #        stats should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @return [Hash<String, Hash<Symbol, Object>>] Each file is returned as a
    #         key in this hash. The value of this key is another hash
    #         containing the stats for this file. Depending on the state of the
    #         file this includes `:added_date`, `:last_modified_date`,
    #         `:last_modified_date` and `'master..development'`.
    # @see Commit#added_files
    # @see Commit#deleted_files
    # @see Commit#modified_files
    def file_stats(range = self.class::DEFAULT_BRANCH)
      support! :line_stats

      stats = {}
      commits(range).each do |commit|
        commit.added_files.each do |file|
          stats[file] = { :modifications => 0 } unless stats.key? file
          stats[file][:added_date] = commit.authored_date
          stats[file][:modifications] += 1
        end
        commit.modified_files.each do |file|
          stats[file] = { :modifications => 0 } unless stats.key? file
          stats[file][:last_modified_date] = commit.authored_date
          stats[file][:modifications] += 1
        end
        commit.deleted_files.each do |file|
          stats[file] = { :modifications => 0 } unless stats.key? file
          stats[file][:deleted_date] = commit.authored_date
        end
      end

      stats
    end

    # This evaluates the changed lines in each commit of the given commit
    # range.
    #
    # For easier use, the values are stored in separate arrays where each
    # number represents the number of changed (i.e. added or deleted) lines in
    # one commit.
    #
    # @example
    #  repo.line_history
    #  => { :additions => [10, 5, 0], :deletions => [0, -2, -1] }
    # @param [String, Range] range The range of commits for which the commit
    #        stats should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @return [Hash<Symbol, Array>] Added lines are returned in an `Array`
    #         assigned to key `:additions`, deleted lines are assigned to
    #         `:deletions`
    # @see Commit#additions
    # @see Commit#deletions
    def line_history(range = self.class::DEFAULT_BRANCH)
      support! :line_stats

      history = { :additions => [], :deletions => [] }
      commits(range).reverse.each do |commit|
        history[:additions] <<  commit.additions
        history[:deletions] << -commit.deletions
      end

      history
    end

    # Returns a list of authors with the biggest impact on the repository, i.e.
    # changing the most code
    #
    # @param [String, Range] range The range of commits for which the authors
    #        should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @param [Fixnum] count The number of authors to return
    # @raise [UnsupportedError] if the VCS does not support `:line_stats`
    # @return [Array<Actor>] An array of the given number of the most
    #         significant authors in the given commit range
    def significant_authors(range = self.class::DEFAULT_BRANCH, count = 3)
      support! :line_stats

      authors = authors(range).values.sort_by { |author| author.modifications }
      count = [count, authors.size].min
      authors[-count..-1].reverse
    end
    alias_method :significant_contributors, :significant_authors

    # Returns a list of commits with the biggest impact on the repository, i.e.
    # changing the most code
    #
    # @param [String, Range] range The range of commits for which the commits
    #        should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @param [Fixnum] count The number of commits to return
    # @raise [UnsupportedError] if the VCS does not support `:line_stats`
    # @return [Array<Actor>] An array of the given number of the most
    #         significant commits in the given commit range
    def significant_commits(range = self.class::DEFAULT_BRANCH, count = 10)
      support! :line_stats

      commits = commits(range).sort_by { |commit| commit.modifications }
      count = [count, commits.size].min
      commits[-count..-1].reverse
    end

    # Returns a list of top contributors in the given commit range
    #
    # This will first have to load all authors (and i.e. commits) from the
    # given commit range.
    #
    # @param [String, Range] range The range of commits for which the top
    #        contributors should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @param [Fixnum] count The number of contributors to return
    # @return [Array<Actor>] An array of the given number of top contributors
    #         in the given commit range
    # @see #authors
    def top_authors(range = self.class::DEFAULT_BRANCH, count = 3)
      authors = authors(range).values.sort_by { |author| author.commits.size }
      count = [count, authors.size].min
      authors[-count..-1].reverse
    end
    alias_method :top_contributors, :top_authors

    private

    # Builds VCS specific commit objects for each given commit's raw data that
    # is provided by the VCS implementation
    #
    # The raw data will be transformed into commit objects that will also be
    # saved into the commit cache. Authors and committers of the given commits
    # will be created and stored into the cache or loaded from the cache if
    # they already exist. Additionally this method will establish an
    # association between the commits and their children.
    #
    # @param [Array<Object>] raw_commits The commits' raw data provided by the
    #        VCS implementation
    # @return [Array<Commit>] The commit objects representing the given commits
    # @see Commit
    # @see Commit#add_child
    def build_commits(raw_commits)
      child_commit_id = nil
      raw_commits.map do |commit|
        commit = self.class::Commit.new(self, commit)
        commit.add_child child_commit_id unless child_commit_id.nil?
        child_commit_id = commit.id
        @commits[commit.id] = commit
        @authors[commit.author.id] = commit.author
        @committers[commit.committer.id] = commit.committer
        commit
      end
    end

    # Tries to retrieve as many commits as possible in the given commit range
    # from the commit cache
    #
    # This method calls itself recursively to walk the given commit range
    # either from the start to the end or vice versa depending on which commit
    # could be found in the cache.
    #
    # @param [Range] range The range of commits which should be retrieved from
    #        the cache. This may be given a range of commit IDs
    #        (`'master'..'development'`).
    # @return [Array<Commit>] A list of commit objects that could be retrieved
    #         from the cache
    # @see Commit#children
    def cached_commits(range)
      commits = []
      if @commits.key? range.last
        commit = @commits[range.last]
        commits << commit
        commit.parents.each do |parent|
          return [] if parent == range.first
          commits += cached_commits range.first..parent
        end
      elsif @commits.key? range.first
        commit = @commits[range.first]
        commits.unshift commit
        commit.children.each do |child|
          return [@commits[child]] if child == range.last
          commits = cached_commits(child..range.last) + commits
        end
      end
      commits
    end

    # Returns the unique identifier for the commit the given reference – like a
    # branch name – is pointing to
    #
    # @abstract Has to be implemented by VCS subclasses
    # @param [String] ref A symbolic reference name
    # @return [Object] The unique identifier of the commit the reference is
    #         pointing to
    def id_for_ref(ref)
      raise NotImplementedError
    end

    # Loads all commits from the given commit range
    #
    # @abstract Has to be implemented by VCS specific subclasses
    # @param [String, Range] range The range of commits for which the commits
    #        should be retrieved. This may be given as a string
    #        (`'master..development'`), a range (`'master'..'development'`) or
    #        as a single ref (`'master'`). A single ref name means all commits
    #        reachable from that ref.
    # @return [Array<Commit>] All commits from the given commit range
    def load_commits(range = self.class::DEFAULT_BRANCH)
      raise NotImplementedError
    end

    # Parses a string or range of commit IDs or ref names into the coresponding
    # range of unique commit IDs
    #
    # @param [String, Range] range The string that should be parsed for a range
    #        or an existing range
    # @return [Range] The range of commit IDs parsed from the given parameter
    # @see #id_for_ref
    def parse_range(range)
      unless range.is_a? Range
        range = range.to_s.split '..'
        range = ((range.size == 1) ? '' : range.first)..range.last
      end

      range = id_for_ref(range.first)..range.last if range.first != ''
      range.first..id_for_ref(range.last)
    end

  end

end
