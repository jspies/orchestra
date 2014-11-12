module Orchestra
  class Performance
    include Observable
    extend Forwardable

    def_delegators :@run_list, :node_names, :provisions, :dependencies,
      :optional_dependencies, :required_dependencies

    attr :input, :state, :registry, :run_list, :thread_pool

    def initialize conductor, run_list, input
      @input = input.dup
      @run_list = run_list
      @registry = conductor.build_registry self
      @state = registry.merge input
      @thread_pool = conductor.thread_pool
    end

    def perform
      ensure_inputs_are_present!
      run_list.each do |name, node| process name, node end
    rescue => error
      publish :error_raised, error
      raise error
    end

    def process name, node
      input = input_for node
      publish :node_entered, name, input
      output = perform_node node
      publish :node_exited, name, output
      state.merge! output
    end

    def perform_node node
      Movement.perform node, state, thread_pool
    end

    def ensure_inputs_are_present!
      has_dep = state.method :has_key?
      missing_input = required_dependencies.reject &has_dep
      raise MissingInputError.new missing_input unless missing_input.empty?
    end

    def input_for node
      state.reject do |key, val|
        registry[key] == val or not node.dependencies.include? key
      end
    end

    def fetch key
      state.fetch key 
    end

    def publish event, *payload
      changed
      notify_observers event, *payload
    end

    class Movement
      def self.perform node, *args
        klass = node.collection ? CollectionMovement : self
        instance = klass.new node, *args
        node.process instance.perform
      end

      attr :context, :node, :state, :thread_pool

      def initialize node, state, thread_pool = ThreadPool.default
        @node = node
        @state = state
        @thread_pool = thread_pool
        @context = node.build_context state
      end

      def perform
        context.perform
      end
    end

    class CollectionMovement < Movement
      def perform
        batch, output = prepare_collection
        jobs = enqueue_jobs batch do |result, index| output[index] = result end
        jobs.each &:wait
        output
      end

      def enqueue_jobs batch, &block
        batch.map.with_index do |element, index|
          enqueue_job element, index, &block
        end
      end

      def enqueue_job element, index
        thread_pool.enqueue do
          result = context.perform element
          yield [result, index]
        end
      end

      def prepare_collection
        batch = context.fetch_collection
        output = [nil] * batch.size
        [batch, output]
      end
    end
  end
end
