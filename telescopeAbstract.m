classdef telescopeAbstract < handle
    % TELESCOPECORE Create a telescopeCore object
    %
    % tel = telescopeCore(D) creates a telescopeCore object from the diameter D.
    %
    % tel = telescopeCore(D,'parameter',value,...) creates a telescopeCore object from
    % the diameter D and from optionnal parameter-value pair arguments. The
    % parameters are obstructionRatio, fieldOfViewInArcsec, fieldOfViewInArcmin
    % or resolution.
    
    properties
        % diameter
        D;
        % central obstruction ratio
        obstructionRatio;
        % conjugation altitude
        conjugationHeight;
        % focalisation distance
        focalDistance;
        % field-of-view
        fieldOfView;
        % diameter resolution in pixel
        resolution;
    end
    
    properties (Dependent)
        % telescope pupil mask
        pupil;
    end
    
    properties (Dependent,SetAccess=private)
        % radius
        R;
        % telescope pupil mask
        pupilLogical;
        % telescope area
        area;
    end
    
    properties (Access=protected)
        p_pupil;
    end
    
    methods
        
        %% Constructor
        function obj = telescopeAbstract(D,varargin)
            p = inputParser;
            p.addRequired('D', @isnumeric);
            p.addParamValue('obstructionRatio', 0, @isnumeric);
            p.addParamValue('conjugationHeight', 0, @isnumeric);
            p.addParamValue('focalDistance', Inf, @isnumeric);
            p.addParamValue('fieldOfViewInArcsec', [], @isnumeric);
            p.addParamValue('fieldOfViewInArcmin', [], @isnumeric);
            p.addParamValue('resolution', [], @isnumeric);
            p.parse(D, varargin{:});
            obj.D                = p.Results.D;
            obj.conjugationHeight = p.Results.conjugationHeight;
            obj.focalDistance = p.Results.focalDistance;
            obj.obstructionRatio = p.Results.obstructionRatio;
            if ~isempty(p.Results.fieldOfViewInArcsec)
                obj.fieldOfView      = p.Results.fieldOfViewInArcsec./cougarConstants.radian2arcsec;
            elseif ~isempty(p.Results.fieldOfViewInArcmin)
                obj.fieldOfView      = p.Results.fieldOfViewInArcmin./cougarConstants.radian2arcmin;
            else
                obj.fieldOfView      = 0;
            end
            obj.resolution       = p.Results.resolution;
        end
        
        function display(obj)
            %% DISPLAY Display object information
            %
            % disp(obj) prints information about the telescope object
            
            if obj.obstructionRatio==0
                fprintf(' %4.2fm diameter full aperture',obj.D)
            else
                fprintf(' %4.2fm diameter with a %4.2f%% central obstruction',...
                    obj.D,obj.obstructionRatio*100)
            end
            fprintf(' with %5.2fm^2 of light collecting area;\n',obj.area)
            if obj.fieldOfView~=0
                fprintf(' the field-of-view is %4.2farcmin;',...
                    obj.fieldOfView*constants.radian2arcmin)
            end
            if ~isempty(obj.resolution)
                fprintf(' the pupil is sampled with %dX%d pixels',...
                    obj.resolution,obj.resolution)
            end
            fprintf('\n')
        end

        %% Get and Set the pupil
        function pupil = get.pupil(obj)
            pupil = obj.p_pupil;
            if isempty(pupil) && ~isempty(obj.resolution)
                pupil = utilities.piston(obj.resolution);
                if obj.obstructionRatio>0
                    pupil = pupil - ...
                        utilities.piston(...
                        round(obj.resolution.*obj.obstructionRatio),...
                        obj.resolution);
                end
            end
        end
        function set.pupil(obj,val)
            obj.p_pupil = val;
        end
        
        function pupilLogical = get.pupilLogical(obj)
            pupilLogical = logical(obj.pupil>0);
        end
        
        function out = get.R(obj)
            out = obj.D/2;
        end
        
        function out = get.area(obj)
            out = pi*obj.R^2*(1-obj.obstructionRatio^2);
        end
        
        function out = diameterAt(obj,height)
            out = obj.D + 2.*height.*tan(obj.fieldOfView/2);
        end
        
        function out = FT(obj,f)
            %$ FT Fourier transform
            %
            % out = FT(obj,f) computes the Fourier transform of the
            % telescope pupil
            
            out   = ones(size(f)).*pi.*obj.D.^2.*(1-obj.obstructionRatio.^2)./4;
            index = f~=0;
            u = pi.*obj.D.*f(index);
            surface = pi.*obj.D.^2./4;
            out(index) = surface.*2.*besselj(1,u)./u;
            if obj.obstructionRatio>0
                u = pi.*obj.D.*obj.obstructionRatio.*f(index);
                surface = surface.*obj.obstructionRatio.^2;
                out(index) = out(index) - surface.*2.*besselj(1,u)./u;
            end
            out = out./(pi.*obj.D.^2.*(1-obj.obstructionRatio.^2)./4);
        end
        
        function out = entrappedEnergy(obj,eHalfSize,trap,psfOrOtf)
            %$ ENTRAPPEDENERGY Encircled of ensquared energy
            %
            % out = entrappedEnergy(obj,eHalfSize,trap) computes the
            % entraped energy in a circle of radius eHalfSize if trap is
            % set to 'circle' or in a square of half length eHalfSize if
            % trap is set to 'square'
            
            if nargin<4
                psfOrOtf = 'psf';
            end
            switch lower(psfOrOtf)
                case 'otf'
                     switch lower(trap)
                        case 'circle'
                            out = 2*pi*quadgk( ...
                                @(r) r.*otf(obj,r).*...
                                (2.*besselj(1,2*pi.*eHalfSize.*r)./(2*pi.*eHalfSize.*r)),0,obj.D)*...
                                pi*eHalfSize^2;
                        case 'square'
                            a = 2*eHalfSize;
                            out = quad2d(...
                                @(o,r) r.*otf(obj,r).*...
                                (sin(pi.*r.*cos(o).*a)./(pi.*r.*cos(o).*a)).*...
                                (sin(pi.*r.*sin(o).*a)./(pi.*r.*sin(o).*a)), ...
                                0,2*pi,0,obj.D).*a.*a;
                        otherwise
                            error('cougar:telescope:entrapedEnergy',...
                                'The trap is either a circle or a square!')
                    end
               otherwise
                    switch lower(trap)
                        case 'circle'
                            out = quadgk(@(x)x.*psf(obj,x),0,eHalfSize)*2*pi;
                        case 'square'
                            out = quad2d(@(x,y)psf(obj,hypot(x,y)),0,eHalfSize,0,eHalfSize)*4;
                        otherwise
                            error('cougar:telescope:entrapedEnergy',...
                                'The trap is either a circle or a square!')
                    end
            end
        end
                
    end
    
    methods (Abstract)
        out = otf(obj, r)
        out = psf(obj,f)  
        out = fullWidthHalfMax(obj)
    end
    
    methods (Static)
                
        function out = symFT(symf)
            syms sD ri s
            u = pi*sD*symf;
            s = pi*sD^2/4;
            out = 2*s*besselj(1,u)/u;
            u = pi*sD*ri*symf;
            s = s*ri^2;
            out = out - 2*s*besselj(1,u)/u;
            out = out/(pi*sD^2*(1-ri^2)/4);
        end
        
    end
    
end
