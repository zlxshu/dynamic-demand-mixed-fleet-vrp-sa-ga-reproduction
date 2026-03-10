function pc = paper_constants()
% PAPER_CONSTANTS - Single source of paper constants (EV key params etc.)
pc = struct();

% EV energy / charging parameters (paper)
pc.B0 = 100;      % kWh
pc.Bmin = 0;      % kWh
pc.Bchg = pc.B0;  % kWh
pc.gE = 1.0;      % kWh/km
pc.rg = 100;      % kWh/h

% CMEM (paper Table 5.1 / opt27 defaults)
cm = struct();
cm.mu   = 44;
cm.phi  = 1;
cm.lam  = 0.2;
cm.H    = 35;
cm.V    = 5;
cm.eta  = 0.9;
cm.eps  = 0.4;
cm.zeta = 737;
cm.eCO2 = 3.09;      % kg/L
cm.rho_air  = 1.225; % kg/m^3
cm.Cr       = 0.010; % rolling resistance coefficient
cm.CdA      = 3.0;   % m^2
cm.m_empty  = 3000;  % kg
cm.rho_fuel = 0.84;  % kg/L
pc.CMEM = cm;

% Prices (keep consistent with existing sections)
pc.elec_price = 0.8;
pc.fuel_price = 7.5;
pc.carbon_price = 0.1;
end
