classdef Optimizer < handle
    properties
        suspension;
        desired_static_char;
        static_char_weights;
        desired_dyn_char;
        dyn_char_weights;
        ds = 0.001;         % differential step size to calc gradient (inches)
        step_size = 0.125;   % step size between states (inches)
        
        static_locations;
        gradients;
        fitnesses;
        
        times = [];
        ax;
        start;
        start_fitness;
        expressions;
        constraints;
        plot_on = 0;
    end
    
    methods (Access = public)
        function self = Optimizer(suspension, max_steps, desired_static_char, static_char_weights, desired_dyn_char, dyn_char_weights)
            self.suspension = suspension;
            num_nodes = length(self.suspension.node_list);
            self.desired_static_char = desired_static_char;
            self.static_char_weights = static_char_weights;
            
            self.desired_dyn_char = desired_dyn_char;
            self.dyn_char_weights = dyn_char_weights;
            
            
            self.start = self.get_current_inputs();
            self.start_fitness = self.get_fitness(self.start);
%             test = self.start + rand(size(self.start)) * 2 - 1;
%             self.get_fitness(self.start)
%             finish = self.get_node_locations();
%             test = self.start + (rand(size(self.start)) * 3 - 1.5);
%             self.get_fitness(test)
            
            [self.expressions, self.constraints] = self.get_inequality_constraints();
            
            self.static_locations = zeros([3, num_nodes, max_steps+1]);
            self.fitnesses = [];
            self.gradients = zeros([num_nodes, max_steps+1]);
            
            l = self.ez_optimize(self.start);
            
            self.get_fitness(l)
            
            disp('final fitness is:')
            min(self.fitnesses)
            
            if self.plot_on
                figure;
                hold on;
                self.ax = gca;
                plot(self.fitnesses)
                f = self.start_fitness;
                plot([1, length(self.fitnesses)], [f, f], 'r--')
                
                figure;
                hold on
                s=self.suspension;
                plot_system_3d('k', s.curr_knuckle, s.curr_pca, s.curr_aca, s.curr_rocker, s.curr_rack, s.curr_pushrod, s.curr_shock);
            end
        end
        
        function l = ez_optimize(self, pos)
            options = optimoptions(@fmincon,'MaxFunctionEvaluations',15000, 'Algorithm', 'sqp');
            l = fmincon(@self.get_fitness, pos, self.expressions, self.constraints, [], [], [], [], [], options);
        end
        
        function optimize(self)
            num_sweeps = 3;
            self.static_locations(:, :, 1) = self.get_node_locations();
            self.fitnesses(1) = self.get_fitness(num_sweeps);
            self.gradients(:, 1) = self.calc_gradient(num_sweeps);
            
            for step = 1:max_steps
                
                curr_fitness = self.get_fitness(num_sweeps);
                gradient = self.calc_gradient(num_sweeps);
                take_step(gradient);
                
                new_fitness = self.get_fitness(num_sweeps);
                if new_fitness < curr_fitness
                    % Accept Move and store info
                    self.static_locations(:, :, step + 1) = self.get_node_locations();
                    self.fitnesses(step + 1) = new_fitness;
                    self.gradients(:, step + 1) = self.calc_gradient(num_sweeps);
                else
                    % Simulated Annealing logic goes here
                    if accept_simulated_annealing
                        % If we accept resutl from simulated annealing
                    else
                        % end simulation
                        fprintf('Local Minimum reached, fitness is %i \n', new_fitness);
                        return
                    end
                end
            end
        end
    end
    
    methods (Access = private)
        function gradient = calc_gradient(self, num_sweeps)
            curr_fitness = get_fitness(num_sweeps);
            nodes = self.suspension.node_list;
            gradient = zeros([1, numel(nodes)]);
            index = 1;
            % Sweep all nodes
            for node = nodes
                % Sweep for each direction
                for direction = 1:3
                    node.location(direction) = node.location(direction) + self.ds;
                    gradient(index) = get_fitness(num_sweeps) - curr_fitness;
                    index = index + 1;
                    node.location(direction) = node.location(direction) - self.ds;
                end
            end
        end
        
        function take_step(self, gradient)
            steps = gradient * norm(gradient) / self.step_size;
            nodes = self.suspension.node_list;
            for index = 1:length(steps)
                node = nodes(index);
                step = steps(index);
                node.location = node.location + step;
            end
        end
        
        function output = get_current_inputs(self)
            output = self.get_node_locations();
            output = [output; self.suspension.get_planar_data()];
        end
        
        function fitness = get_fitness(self, inputs)
            num_sweeps = 3;
            tic
            self.update_inputs(inputs);
%             clf;
%             hold on;
%             s = self.suspension;
%             plot_system_3d('k', s.curr_rocker, s.curr_shock, s.curr_aca, s.curr_pushrod, s.curr_pca, s.curr_knuckle);
%             drawnow()
            [static_char, dyn_char] = self.suspension.perform_sweep(num_sweeps, 0);
            
            fitness = calc_fitness(static_char, dyn_char, self.desired_static_char, self.static_char_weights, self.desired_dyn_char, self.dyn_char_weights);
            self.fitnesses(end + 1) = fitness;
            self.times(end+1) = toc;
        end
        
        function locations = get_node_locations(self)
            nodes = self.suspension.node_list;
            locations = zeros([3, length(nodes)]);
            for index = 1:length(nodes)
                locations(:,index) = nodes(index).location;
            end
            locations = reshape(locations, [numel(locations), 1]);
        end

        function update_inputs(self, inputs)
            new_locations = inputs(1:end-3);
            planar_inputs = inputs(end-2:end);
            new_locations = reshape(new_locations, [3, numel(new_locations)/3]);
            nodes = self.suspension.node_list;
            for index = 1:length(nodes)
                nodes(index).location = new_locations(:, index);
            end
            self.suspension.update_planar_nodes(planar_inputs);
            self.suspension.update_all();
            new_locations = [];
        end

        
        function [expressions, constraints] = get_inequality_constraints(self)
            nodes = self.suspension.node_list;
            n = length(nodes);
            
            % The size of this matrix is enough to hold the constraints
            % related to all nodes and planar inputs. 
            A = zeros([6*n + 6, 3*n + 3 + 1]);
            
            % populare node contraints into A
            region_lims = {'max_x', 'min_x', 'max_y', 'min_y', 'max_z', 'min_z'};
            for index = 1:n
                for dimension = 1:3
                    row = (index - 1) * 6 + (dimension - 1) * 2 + 1;
                    col = (index - 1) * 3 + dimension;
                    limit_index = (dimension - 1) * 2 + 1;
                    A(row, col) = 1; 
                    A(row + 1, col) = -1;
                    A(row, end) = nodes(index).region.(region_lims{limit_index});
                    A(row + 1, end) = -nodes(index).region.(region_lims{limit_index + 1});
                end
            end
            shock_angle = self.start(end-2);
            pushrod_angle = self.start(end-1);
            
            % Shock angle limits
            A([end-5, end-4], [end-3, end]) = [sign(shock_angle), sign(shock_angle) * (shock_angle + sign(shock_angle) * 0);...
                                              -sign(shock_angle), sign(shock_angle) * (-shock_angle + sign(shock_angle) * 0)];
            % pushrod angle limits
            A([end-3, end-2], [end-2, end]) = [sign(pushrod_angle), sign(pushrod_angle) * (pushrod_angle + sign(pushrod_angle) * 0);...
                                              -sign(pushrod_angle), sign(pushrod_angle) * (-pushrod_angle + sign(pushrod_angle) * 0)];
            % length limits
%             A([end-1, end], [end-1, end]) = [1, 18; -1, -10];
            A([end-1, end], [end-1, end]) = [1, 13.52; -1, -13.52];
            
            
            expressions = A(:, 1:end-1);
            constraints = A(:, end);
        end
    end
        
        
end