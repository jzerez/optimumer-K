classdef Plane < handle
   properties
        position;
        normal;
        i_hat;
        j_hat;
   end
   
   methods
        function self = Plane(varargin)
            % Constructor Function. Can define plane by 3 points, or two
            % vectors that are in plane
            if nargin > 2
               % Defined by 3 Points
               self.position = varargin{1};
               v1 = varargin{2} - varargin{1};
               v2 = varargin{3} - varargin{1};
               self.normal = unit(cross(v1, v2));
            elseif isa(varargin{1}, 'Line') && isa(varargin{2}, 'Line')
                % Defined by 2 Planar Line Segments
                line1 = varargin{1};
                line2 = varargin{2};
                self.position = line1.position;
                self.normal = unit(cross(line1.axis, line2.axis));
            else
               % Defined by a normal vector and a point
               self.position = varargin{1};
               self.normal = varargin{2};
           end
           
           self.update();
       end
       
       function res = is_in_plane(self, point)
            v = unit(point - self.position);
            if isnan(v)
                res = true;
                return
            end
            dist = abs(dot(v, self.normal));
            if dist < 1e-8
                res = true;
                return
            end
            res = false;
            disp('dist to point is:')
            disp(dist)
        end
       
        function new_point = project_into_plane(self, point)
            norm_dist = self.calc_norm_dist(point);
            new_point = point - (norm_dist*self.normal);
            assert(self.is_in_plane(new_point))
        end
       
        function r2_points = convert_to_planar_coor(self, points)

            r2_points = zeros([2, size(points, 2)]);
            for index = 1:size(points,2)
                if ~self.is_in_plane(points)
                    disp('not in plane, cannot convert to planar coor')
                end
                v = points(:, index) - self.position;
                i_mag = dot(v, self.i_hat);
                j_mag = dot(v, self.j_hat);
                r2_points(:, index) = [i_mag;j_mag];
            end
        end
       
       function r3_points = convert_to_global_coor(self, points)
            r3_points = zeros([3, size(points, 2)]);
            for index = 1:size(points,2)
                p_2d = points(:, index);
                p_3d = p_2d(1)*self.i_hat + p_2d(2)*self.j_hat;
                %assert(self.is_in_plane(p_3d + self.position))
                r3_points(:, index) = p_3d + self.position;
            end
       end
       
       function norm_dist = calc_norm_dist(self, point)
            dist = point - self.position;
            norm_dist = dot(dist, self.normal);
       end
       
       function [point, vector] = calc_plane_plane_int(self, plane)
            % calculates the intersection between two planes
            
            % If the two planes are parallel
            if abs(dot(plane.normal, self.normal)) == 1
                point = NaN;
                vector = NaN;
                return;
            end
            
            % Vector of the line between the planes' intersection
            vector = unit(cross(self.normal, plane.normal));
            
            % 
            m = plane.calc_norm_dist(self.position);
            w = plane.normal;
            
            % Projection of the other plane's normal vector into current
            % plane
            v = self.project_into_plane(self.position + w) - self.position;
            
            % Cover the normal distance, m, by looking at the component of
            % the normal vector, w, by the appropriate amount w;
            n = m / dot(v,w);
            point = self.position - n*v;
       end
       
       function update(self)
          if isequal(self.normal, [1;0;0])
                ibase = [0; 1; 0];
           else
                ibase = [1; 0; 0];
           end
           self.i_hat = unit(self.project_into_plane(self.position + ibase) - self.position);
           self.j_hat = cross(self.normal, self.i_hat);
           assert(self.is_in_plane([self.i_hat+self.j_hat+self.position])) 
       end
   end
end