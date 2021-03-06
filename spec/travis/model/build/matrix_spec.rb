require 'spec_helper'

describe Build, 'matrix' do
  include Support::ActiveRecord

  before { Build.send :public, :matrix_config, :expand_matrix_config }
  after  { Build.send :protected, :matrix_config, :expand_matrix_config }

  describe :matrix_finished? do
    context "if at least one job has not finished" do
      it 'returns false' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'] })
        build.matrix[0].update_attributes(:state => :finished)
        build.matrix[1].update_attributes(:state => :started)

        build.matrix_finished?.should_not be_true
      end
    end

    context "if all jobs have finished" do
      it 'returns true' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'] })
        build.matrix[0].update_attributes!(:state => :finished)
        build.matrix[1].update_attributes!(:state => :finished)

        build.matrix_finished?.should_not be_nil
      end
    end
  end

  describe :matrix_result do
    context "if any job has the result 1" do
      it 'returns 1 ' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'] })
        build.matrix[0].update_attributes!(:result => 1, :state => :finished)
        build.matrix[1].update_attributes!(:result => 0, :state => :finished)
        build.matrix_result.should == 1
      end
    end

    context "if all jobs have the result 0" do
      it 'returns 0' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'] })
        build.matrix[0].update_attributes!(:result => 0, :state => :finished)
        build.matrix[1].update_attributes!(:result => 0, :state => :finished)
        build.matrix_result.should == 0
      end
    end

    context "if a failed job is allowed to fail" do
      it 'returns 0' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'] })
        build.matrix[0].update_attributes!(:result => 0, :state => :finished)
        build.matrix[1].update_attributes!(:result => 1, :state => :finished, :allow_failure => true)
        build.matrix_result.should == 0
      end
    end

    context "if all jobs fail and one is allowed to fail" do
      it 'returns 1' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'] })
        build.matrix[0].update_attributes!(:result => 1, :state => :finished)
        build.matrix[1].update_attributes!(:result => 1, :state => :finished, :allow_failure => true)
        build.matrix_result.should == 1
      end
    end
  end

  describe :matrix_duration do
    let(:build) do
      Build.new(:matrix => [
        Job::Test.new(:started_at => 60.seconds.ago, :finished_at => 40.seconds.ago),
        Job::Test.new(:started_at => 20.seconds.ago, :finished_at => 10.seconds.ago)
       ])
    end

    context "if the matrix is finished" do
      it 'returns the sum of the matrix job durations' do
        build.stubs(:matrix_finished?).returns(true)
        build.matrix_duration.should == 30
      end
    end

    context "if the matrix is not finished" do
      it 'returns nil' do
        build.stubs(:matrix_finished?).returns(false)
        build.matrix_duration.should be_nil
      end
    end
  end



  describe "for Ruby projects" do
    let(:no_matrix_config) {
      YAML.load <<-yml
      script: "rake ci"
    yml
    }

    let(:encrypted_and_unencrypted_config) {
    YAML.load <<-yml
      script: "rake ci"
      rvm:
        - 1.8.7
      gemfile:
        - gemfiles/rails-3.0.6
      env:
        - ["TO=ENCRYPT", "FOO=BAR"]
    yml
    }

    let(:single_test_config) {
      YAML.load <<-yml
      script: "rake ci"
      rvm:
        - 1.8.7
      gemfile:
        - gemfiles/rails-3.0.6
      env:
        - USE_GIT_REPOS=true
    yml
    }

    let(:multiple_tests_config) {
      YAML.load <<-yml
      script: "rake ci"
      rvm:
        - 1.8.7
        - 1.9.1
        - 1.9.2
      gemfile:
        - gemfiles/rails-3.0.6
        - gemfiles/rails-3.0.7
        - gemfiles/rails-3-0-stable
        - gemfiles/rails-master
      env:
        - USE_GIT_REPOS=true
    yml
    }

    let(:multiple_tests_config_with_exculsion) {
      YAML.load <<-yml
      rvm:
        - 1.8.7
        - 1.9.2
      gemfile:
        - gemfiles/rails-2.3.x
        - gemfiles/rails-3.0.x
        - gemfiles/rails-3.1.x
      matrix:
        exclude:
          - rvm: 1.8.7
            gemfile: gemfiles/rails-3.1.x
          - rvm: 1.9.2
            gemfile: gemfiles/rails-2.3.x
    yml
    }

    let(:multiple_tests_config_with_invalid_exculsion) {
      YAML.load <<-yml
      rvm:
        - 1.8.7
        - 1.9.2
      gemfile:
        - gemfiles/rails-3.0.x
        - gemfiles/rails-3.1.x
      env:
        - FOO=bar
        - BAR=baz
      matrix:
        exclude:
          - rvm: 1.9.2
            gemfile: gemfiles/rails-3.0.x
    yml
    }

    let(:multiple_tests_config_with_inclusion) {
      YAML.load <<-yml
      rvm:
        - 1.8.7
        - 1.9.2
      env:
        - FOO=bar
        - BAR=baz
      matrix:
        include:
          - rvm: 1.9.2
            env: BAR=xyzzy
    yml
    }

    let(:multiple_tests_config_with_allow_failures) {
      YAML.load <<-yml
      rvm:
        - 1.8.7
        - 1.9.2
      gemfile:
        - gemfiles/rails-2.3.x
        - gemfiles/rails-3.0.x
        - gemfiles/rails-3.1.x
      matrix:
        allow_failures:
          - rvm: 1.9.2
            gemfile: gemfiles/rails-2.3.x
    yml
    }

    describe :expand_matrix_config do
      def encrypt_config_env(config, repository)
        config['env'] = config.delete('env').map { |env| repository.key.secure.encrypt(env) }
      end

      it 'expands the build matrix configuration (single test config)' do
        build = Factory(:build, :config => single_test_config)
        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'], [:env, 'USE_GIT_REPOS=true']],
        ]
      end

      it 'decrypts only the part of env setting that needs to be decrypted' do
        repository = Factory(:repository)

        # Encrypt first of given values
        env = encrypted_and_unencrypted_config['env'][0]
        env[0] = repository.key.secure.encrypt(env[0])

        # Ensure that first env var is encrypted
        encrypted_and_unencrypted_config['env'][0][0].should have_key('secure')

        build      = Factory(:build, :config => encrypted_and_unencrypted_config, :repository => repository)
        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'], [:env, ["SECURE TO=ENCRYPT", "FOO=BAR"]]]
        ]
      end

      it 'decrypts a secure env configuration (single test config)' do
        repository = Factory(:repository)

        encrypt_config_env(single_test_config, repository)

        build      = Factory(:build, :config => single_test_config, :repository => repository)
        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'], [:env, 'SECURE USE_GIT_REPOS=true']]
        ]
      end

      it 'leaves unencrypted env vars for pull_requests (single test config)' do
        repository = Factory(:repository)
        request    = Factory(:request)

        single_test_config['env'] << repository.key.secure.encrypt("FOO=bar")

        request.expects(:pull_request?).at_least_once.returns(true)
        build = Factory(:build, :config => single_test_config,
                                :repository => repository,
                                :request => request)

        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'], [:env, 'USE_GIT_REPOS=true']]
        ]
      end


      it 'removes encrypted env vars instead of decrypting them for pull_requests (single test config)' do
        repository = Factory(:repository)
        request    = Factory(:request)

        encrypt_config_env(single_test_config, repository)

        request.expects(:pull_request?).at_least_once.returns(true)
        build = Factory(:build, :config => single_test_config,
                                :repository => repository,
                                :request => request)

        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6']]
        ]
      end

      it 'removes encrypted env vars instead of decrypting them for pull_requests (encrypted and unencrypted values in env)' do
        repository = Factory(:repository)
        request    = Factory(:request)

        # Encrypt first of given values
        env = encrypted_and_unencrypted_config['env'][0]
        env[0] = repository.key.secure.encrypt(env[0])

        # Ensure that first env var is encrypted
        encrypted_and_unencrypted_config['env'][0][0].should have_key('secure')

        request.expects(:pull_request?).at_least_once.returns(true)
        build      = Factory(:build, :config => encrypted_and_unencrypted_config,
                                     :repository => repository,
                                     :request => request)
        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'], [:env, "FOO=BAR"]]
        ]
      end

      it 'leaves unencrypted env vars for pull_requests (multiple test config)' do
        repository = Factory(:repository)
        request    = Factory(:request)

        multiple_tests_config['env'] << repository.key.secure.encrypt("FOO=bar")

        request.expects(:pull_request?).at_least_once.returns(true)
        build = Factory(:build, :config => multiple_tests_config,
                                :repository => repository,
                                :request => request)

        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.7'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3-0-stable'], [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-master'],     [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3.0.6'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3.0.7'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3-0-stable'], [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-master'],     [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3.0.6'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3.0.7'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3-0-stable'], [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-master'],     [:env, 'USE_GIT_REPOS=true']]
         ]
      end

      it 'removes encrypted env vars instead of decrypting them for pull_requests (multiple test config)' do
        repository = Factory(:repository)
        request    = Factory(:request)

        encrypt_config_env(multiple_tests_config, repository)

        request.expects(:pull_request?).at_least_once.returns(true)
        build = Factory(:build, :config => multiple_tests_config,
                                :repository => repository,
                                :request => request)

        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6']     ],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.7']     ],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3-0-stable']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-master']    ],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3.0.6']     ],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3.0.7']     ],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3-0-stable']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-master']    ],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3.0.6']     ],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3.0.7']     ],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3-0-stable']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-master']    ]
         ]
      end

      it 'expands the build matrix configuration (multiple tests config)' do
        build = Factory(:build, :config => multiple_tests_config)
        build.expand_matrix_config(build.matrix_config).should == [
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.6'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3.0.7'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-3-0-stable'], [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.8.7'], [:gemfile, 'gemfiles/rails-master'],     [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3.0.6'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3.0.7'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-3-0-stable'], [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.1'], [:gemfile, 'gemfiles/rails-master'],     [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3.0.6'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3.0.7'],      [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-3-0-stable'], [:env, 'USE_GIT_REPOS=true']],
          [[:rvm, '1.9.2'], [:gemfile, 'gemfiles/rails-master'],     [:env, 'USE_GIT_REPOS=true']]
         ]
      end
    end

    describe :expand_matrix do
      it 'sets the config to the jobs (no config)' do
        build = Factory(:build, :config => {})
        build.matrix.map(&:config).should == [{}]
      end

      it 'sets the config to the jobs (no matrix config)' do
        build = Factory(:build, :config => no_matrix_config)
        build.matrix.map(&:config).should == [{ :script => 'rake ci' }]
      end

      it 'sets the config to the jobs (single test config)' do
        build = Factory(:build, :config => single_test_config)
        build.matrix.map(&:config).should == [
          { :script => 'rake ci', :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.0.6', :env => 'USE_GIT_REPOS=true' }
        ]
      end

      it 'sets the config to the jobs (multiple tests config)' do
        build = Factory(:build, :config => multiple_tests_config)
        build.matrix.map(&:config).should == [
          { :script => 'rake ci', :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.0.6',      :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.0.7',      :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3-0-stable', :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.8.7', :gemfile => 'gemfiles/rails-master',     :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.1', :gemfile => 'gemfiles/rails-3.0.6',      :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.1', :gemfile => 'gemfiles/rails-3.0.7',      :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.1', :gemfile => 'gemfiles/rails-3-0-stable', :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.1', :gemfile => 'gemfiles/rails-master',     :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.0.6',      :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.0.7',      :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3-0-stable', :env => 'USE_GIT_REPOS=true' },
          { :script => 'rake ci', :rvm => '1.9.2', :gemfile => 'gemfiles/rails-master',     :env => 'USE_GIT_REPOS=true' }
        ]
      end

      it 'sets the config to the jobs (allow failures config)' do
        build = Factory(:build, :config => multiple_tests_config_with_allow_failures)
        build.matrix.map(&:allow_failure).should == [false, false, false, true, false, false]
      end

      it 'copies build attributes' do
        # TODO spec other attributes!
        build = Factory(:build, :config => multiple_tests_config)
        build.matrix.map(&:commit_id).uniq.should == [build.commit_id]
      end

      it 'adds a sub-build number to the job number' do
        build = Factory(:build, :config => multiple_tests_config)
        build.matrix.map(&:number)[0..3].should == ['1.1', '1.2', '1.3', '1.4']
      end

      describe :exclude_matrix_config do
        it 'excludes a matrix config when all config items are defined in the exclusion' do
          build = Factory(:build, :config => multiple_tests_config_with_exculsion)
          matrix_exclusion = {
            :exclude => [
              { :rvm => "1.8.7", :gemfile => "gemfiles/rails-3.1.x" },
              { :rvm => "1.9.2", :gemfile => "gemfiles/rails-2.3.x" }
            ]
          }

          build.matrix.map(&:config).should == [
            { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-2.3.x', :matrix => matrix_exclusion },
            { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.0.x', :matrix => matrix_exclusion },
            { :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.0.x', :matrix => matrix_exclusion },
            { :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.1.x', :matrix => matrix_exclusion }
          ]
        end

        it 'does not exclude a matrix config when the matrix exclusion definition is incomplete' do
          build = Factory(:build, :config => multiple_tests_config_with_invalid_exculsion)

          matrix_exclusion = { :exclude => [{ :rvm => "1.9.2", :gemfile => "gemfiles/rails-3.0.x" }] }

          build.matrix.map(&:config).should == [
            { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.0.x', :env => 'FOO=bar', :matrix => matrix_exclusion },
            { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.0.x', :env => 'BAR=baz', :matrix => matrix_exclusion },
            { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.1.x', :env => 'FOO=bar', :matrix => matrix_exclusion },
            { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-3.1.x', :env => 'BAR=baz', :matrix => matrix_exclusion },
            { :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.0.x', :env => 'FOO=bar', :matrix => matrix_exclusion },
            { :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.0.x', :env => 'BAR=baz', :matrix => matrix_exclusion },
            { :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.1.x', :env => 'FOO=bar', :matrix => matrix_exclusion },
            { :rvm => '1.9.2', :gemfile => 'gemfiles/rails-3.1.x', :env => 'BAR=baz', :matrix => matrix_exclusion }
          ]
        end
      end
    end

    describe :include_matrix_config do
      it 'includes a matrix config' do
          build = Factory(:build, :config => multiple_tests_config_with_inclusion)

          matrix_inclusion = {
            :include => [
              { :rvm => '1.9.2', :env => 'BAR=xyzzy' }
            ]
          }

          build.matrix.map(&:config).should == [
            { :rvm => '1.8.7', :env => 'FOO=bar', :matrix => matrix_inclusion },
            { :rvm => '1.8.7', :env => 'BAR=baz', :matrix => matrix_inclusion },
            { :rvm => '1.9.2', :env => 'FOO=bar', :matrix => matrix_inclusion },
            { :rvm => '1.9.2', :env => 'BAR=baz', :matrix => matrix_inclusion },
            { :rvm => '1.9.2', :env => 'BAR=xyzzy', :matrix => matrix_inclusion },
          ]
        end
    end

    describe :matrix_config do
      let(:repository) { Factory(:repository) }

      it 'with string values' do
        build = Factory(:build, :config => { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-2.3.x', :env => 'FOO=bar' })
        expected = [
          [[:rvm,     '1.8.7']],
          [[:gemfile, 'gemfiles/rails-2.3.x']],
          [[:env,     'FOO=bar']]
        ]
        build.matrix_config.should == expected
      end

      it 'strings with a secure env' do
        build = Factory(:build, :repository => repository, :config => { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-2.3.x', :env => repository.key.secure.encrypt('FOO=bar') })
        expected = [
                    [[:rvm,     '1.8.7']],
                    [[:gemfile, 'gemfiles/rails-2.3.x']],
                    [[:env,     'SECURE FOO=bar']]
                   ]
        build.matrix_config.should == expected
      end

      it 'with two Rubies and Gemfiles' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'], :gemfile => ['gemfiles/rails-2.3.x', 'gemfiles/rails-3.0.x'] })
        expected = [
          [[:rvm, '1.8.7'], [:rvm, '1.9.2']],
          [[:gemfile, 'gemfiles/rails-2.3.x'], [:gemfile, 'gemfiles/rails-3.0.x']]
        ]
        build.matrix_config.should == expected
      end

      it 'with unequal number of Rubies, env variables and Gemfiles' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2', 'ree'], :gemfile => ['gemfiles/rails-3.0.x'], :env => ['DB=postgresql', 'DB=mysql'] })
        build.matrix_config.should == [
          [[:rvm, '1.8.7'], [:rvm, '1.9.2'], [:rvm, 'ree']],
          [[:gemfile, 'gemfiles/rails-3.0.x'], [:gemfile, 'gemfiles/rails-3.0.x'], [:gemfile, 'gemfiles/rails-3.0.x']],
          [[:env, 'DB=postgresql'], [:env, 'DB=mysql'], [:env, 'DB=mysql']]
        ]
      end

      it 'with an array of Rubies and a single Gemfile' do
        build = Factory(:build, :config => { :rvm => ['1.8.7', '1.9.2'], :gemfile => 'gemfiles/rails-2.3.x' })
        build.matrix_config.should == [
          [[:rvm, '1.8.7'], [:rvm, '1.9.2']],
          [[:gemfile, 'gemfiles/rails-2.3.x'], [:gemfile, 'gemfiles/rails-2.3.x']]
        ]
      end

      it 'with secure and insecure envs' do
        build = Factory(:build, :repository => repository, :config => { :rvm => '1.8.7', :gemfile => 'gemfiles/rails-2.3.x', :env => [repository.key.secure.encrypt('FOO=bar'), 'FOO=baz'] })
        expected = [
                    [[:rvm, '1.8.7'], [:rvm, '1.8.7']],
                    [[:gemfile, 'gemfiles/rails-2.3.x'], [:gemfile, 'gemfiles/rails-2.3.x']],
                    [[:env, 'SECURE FOO=bar'], [:env, 'FOO=baz']]
                   ]
        build.matrix_config.should == expected
      end
    end
  end

  describe "for Scala projects" do
    it 'with a single Scala version given as a string' do
      build = Factory(:build, :config => { :scala => '2.8.2', :env => 'NETWORK=false' })
      expected = [
        [[:env, 'NETWORK=false']],
        [[:scala, '2.8.2']]
      ]
      build.matrix_config.should == expected
    end

    it 'with multiple Scala versions and no env variables' do
      build = Factory(:build, :config => { :scala => ['2.8.2', '2.9.1']})
      expected = [
         [[:scala, '2.8.2'], [:scala, '2.9.1']]
       ]
      build.matrix_config.should == expected
    end

    it 'with a single Scala version passed in as array and two env variables' do
      build = Factory(:build, :config => { :scala => ['2.8.2'], :env => ['STORE=postgresql', 'STORE=redis'] })
      build.matrix_config.should == [
        [[:env, 'STORE=postgresql'], [:env, 'STORE=redis']],
        [[:scala, '2.8.2'], [:scala, '2.8.2']]
      ]
    end
  end



  describe 'matrix_for' do
    it 'selects matching builds' do
      build = Factory(:build, :config => { 'rvm' => ['1.8.7', '1.9.2'], 'env' => ['DB=sqlite3', 'DB=postgresql'] })
      build.matrix_for({ 'rvm' => '1.8.7', 'env' => 'DB=sqlite3' }).should == [build.matrix[0]]
    end

    it 'does not select builds with non-matching values' do
      build = Factory(:build, :config => { 'rvm' => ['1.8.7', '1.9.2'], 'env' => ['DB=sqlite3', 'DB=postgresql'] })
      build.matrix_for({ 'rvm' => 'nomatch', 'env' => 'DB=sqlite3' }).should be_empty
    end

    it 'does not select builds with non-matching keys' do
      build = Factory(:build, :config => { 'rvm' => ['1.8.7', '1.9.2'], 'env' => ['DB=sqlite3', 'DB=postgresql'] })
      build.matrix_for({ 'rvm' => '1.8.7', 'nomatch' => 'DB=sqlite3' }).should == [build.matrix[0], build.matrix[1]]
    end
  end

  describe 'matrix_keys_for' do
    it 'only selects ENV_KEYS' do
      Build::Matrix::ENV_KEYS.each do |key|
        Build.matrix_keys_for('invalid key' => 'invalid', key => 'valid').should == [key]
      end
    end

    it 'selects symbolized ENV_KEYS' do
      Build::Matrix::ENV_KEYS.each do |key|
        Build.matrix_keys_for(key => 'valid').should == [key]
      end
    end
  end
end
