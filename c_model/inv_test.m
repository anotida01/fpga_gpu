
camera_x = 7.3589; camera_y = -6.9258; camera_z = 4.9583;
% alpha_x = -63.6*pi/180; beta_y = 0; gamma_z = -46.7*pi/180;
alpha_x = 63.6*pi/180; beta_y = 0; gamma_z = 46.7*pi/180;

% w2c = [
%     [cos(beta_y)*cos(gamma_z),  sin(alpha_x)*sin(beta_y)*cos(gamma_z)-cos(alpha_x)*sin(gamma_z)...
%     cos(alpha_x)*sin(beta_y)*cos(gamma_z)+sin(alpha_x)*sin(gamma_z), -1*camera_x];

%     [cos(beta_y)*sin(gamma_z),  sin(alpha_x)*sin(beta_y)*sin(gamma_z) + cos(alpha_x)*cos(gamma_z)...
%     cos(alpha_x)*sin(beta_y)*cos(gamma_z) - sin(alpha_x)*cos(gamma_z), -1*camera_y];

%     [-sin(beta_y), sin(alpha_x)*cos(beta_y), cos(alpha_x)*cos(beta_y), -1*camera_z];

%     [0, 0, 0, 1]
% ]

w2c = [
    [cos(beta_y)*cos(gamma_z),  sin(alpha_x)*sin(beta_y)*cos(gamma_z)-cos(alpha_x)*sin(gamma_z)...
    cos(alpha_x)*sin(beta_y)*cos(gamma_z)+sin(alpha_x)*sin(gamma_z), 1*camera_x];

    [cos(beta_y)*sin(gamma_z),  sin(alpha_x)*sin(beta_y)*sin(gamma_z) + cos(alpha_x)*cos(gamma_z)...
    cos(alpha_x)*sin(beta_y)*cos(gamma_z) - sin(alpha_x)*cos(gamma_z), 1*camera_y];

    [-sin(beta_y), sin(alpha_x)*cos(beta_y), cos(alpha_x)*cos(beta_y), 1*camera_z];

    [0, 0, 0, 1]
]

inv_w2c = inv(w2c)



