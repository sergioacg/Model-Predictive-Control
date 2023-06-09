%% MIMO DTC-GPC for Wood an Berry column
% Sergio Andres Casta�o Giraldo
% http://controlautomaticoeducacion.com/
% Federal University of Rio de Janeiro
% Rio de Janeiro - 2018
% Using the Diophantine Method
% The Optimal Predictor should be used and the minimal delays of the fast
% model should be used for the calculation of past controls
% THE SYSTEM IS CONDITIONED
%_____________________________________________________________________

clc
close all
clear all

%% Define the process of the Column:
% Uncertainties for simulation
deltak=0.0;     % Fixed value of uncertainty in gain
deltaL=0.0;     % Fixed value of uncertainty in delay
Ts=1;           % Sampling Period

%% System with delay and uncertainty
P=[tf(12.8,[16.7 1])*(1+deltak) tf(-18.9,[21 1])*(1+deltak);
   tf(6.6,[10.9 1])*(1+deltak) tf(-19.4,[14.4 1])*(1+deltak)];
P.iodelay=[1 2;2 1]+deltaL;

%Nominal model of the process
Pn=[tf(12.8,[16.7 1]) tf(-18.9,[21 1]);tf(6.6,[10.9 1]) tf(-19.4,[14.4 1])];
Pn.iodelay=[1 2;2 1];

Pq = [tf(3.8,[14.9 1]); tf(4.9,[13.2 1])];
Pq.iodelay = [8.1; 3.4];

%% Conditioning
Kn=dcgain(Pn);              %Gain matrix of the model
[L,R] = CondMin(Kn);        %Conditioned algorithm
Pne=L*Pn*R;                 %Conditioned Nominal model
[my,ny]=size(Pne);          %Number of inputs (ny) and Outputs (my)

%% Discretization of models
Pnz=c2d(Pne,Ts);                 % Discrete Conditioned Nominal model
[Bp,Ap,dp]=descompMPC(Pnz);      % Decomposes num, den and delay of Pz into cells

%Find out the minimum delay in my transfer function
dmin=[100 100]';
for i=1:2
    dmin(i)=min(dp(i,:));
end

%% Fast Model
dreal=Pnz.iodelay;
Gnz=Pnz;
Gnz.iodelay=dreal-diag(dmin)*ones(my,ny);
dnz=dp-diag(dmin)*ones(my,ny);

nit=200;    % Number of iterations

%% GPC Tuning Parameters
p=[3;3];                        % Prediction Window
N1=[dmin(1)+1 dmin(2)+1];       % Initial Horizon
N2=[dmin(1)+p(1) dmin(2)+p(2)]; % Final Horizon
m=[3;3];                        % Control Horizon
lambda=[1 1];                   % Control action weighting
delta=[1 1];                    % Reference tracking weighting

% positive semidefinite weight matrices
W=[];
for i=1:ny
    W=blkdiag(W,lambda(i)*eye(m(i)));  %(W -> Control Action)
end
W=sparse(W);
Q=[];
for i=1:my
    Q=blkdiag(Q,delta(i)*eye(p(i)));  %(Q  -> Reference Tracking)
end
Q=sparse(Q);

%% Calculation of the Diophantine equation
[B,A,na,nb] = BA_MIMO(Bp,Ap);
[E,En,F] = diophantineMIMO(A,p,[0,0]);

% Block matrix S with the coefficients of the free response (polynomial F)
S=[];
for i=1:my
    S=blkdiag(S,F{i}(1:p(i),1:end)); 
end

%% Matrix of the Forced Response G
[H] = MatG(Pnz,p,m,dp);

%Determine the Vector with past controls using the function:
uG = deltaUFree(B,En,p,dnz);
Hp = cell2mat2(uG);     %Polynomial with past controls
duM=max(nb+dnz);        %DTC-GPC
up=zeros(sum(duM),1);   %Vector Past Controls

%Sistem without constraints
S1=H'*Q*H+W;
S1=(S1+S1')/2;
K=S1\H'*Q;    %K Gain

Km(1,:)=K(1,:);                   %Take only the first column (for control u1)
for i=1:ny-1
    Km(i+1,:)=K(sum(m(1:i))+1,:); %Take K values from [N(1)+1] one sample after the first 
end                               %control horizon (for control u2)

%% Fr and S Filter
[So,Fr]=mimofilter(Pnz,0.7,0.8,2);

%% Control Loop
% initializes Simulation parameters
ref={zeros(p(1),1)};
% Signals of the MIMO 2x2 process (Initialization)
y(1:my,1:nit) = 0;  %Process Output
ye(1:my,1:nit) = 0; %Process conditioned Output
yq(1:my,1:nit) = 0;  %Process Disturbance Output
r(1:my,1:nit) = 0;  %Reference
r(1,11:nit) = 0.8;
r(2,61:nit) = 0.5;
re(1:my,1:nit) =L*r;  %Conditioned Reference
u(1:ny,1:nit) = 0;    %Control action
ue(1:ny,1:nit) = R\u; %Conditioned Control Action 
q(1,1:nit) = 0;    %Disturbance
q(1,141:nit) = -0.25;
deltaU=zeros(length(m),1); %Control increment

%Start the Control loop
for k=4:nit
     %% Output of the Real MIMO process
      t = 0:Ts:(k-1)*Ts;
      yq=lsim(Pq,q(:,1:k),t,'zoh')';
      y=lsim(P,u(:,1:k),t,'zoh')' + yq;
      ye=L*y; %Conditioned
      
      %% Calculation of the Optimal Predictor
      yp = OptimalPredictor2(Fr,Pnz,Gnz,ue,ye,k);
      
      %% Calculation of the free response
     Yd=[];
     for j=1:my
         Yd=[Yd yp(j,k:-1:k-na(j))];
     end
     for i=1:my
          Ref(sum(p(1:i-1))+1:sum(p(1:i)),1)=re(i,k);
     end
     yf=Hp*up+S*Yd';
     
     %Control Increment
     deltaU=Km*(Ref-yf); 
     
    % Update vectors of Past Controls 
    for i=1:ny
        aux_1=up(sum(duM(1:i-1))+1:sum(duM(1:i))-1);
        up(sum(duM(1:i-1))+1:sum(duM(1:i)))=[deltaU(i); aux_1];
    end
    
     %% Calculation of the control law
     if k==1
        ue(:,k)=deltaU;
     else
        ue(:,k)=ue(:,k-1)+ deltaU;
     end
     u(:,k)=R*ue(:,k);
end

FS = 24;
figure(1)
subplot(2,1,1)
hold on
plot(t,r,'--r',t,y,'-b','linewidth',3),grid;
ylabel('$$\rm  mol/mol$$','FontSize',FS,'Interpreter','latex')
xlabel('$$\rm time\ (min)$$','FontSize',FS,'Interpreter','latex')
text(17,0.6,'$$\leftarrow y_1$$','FontSize',FS,'Interpreter','latex')
text(64,0.3,'$$\leftarrow y_2$$','FontSize',FS,'Interpreter','latex')
set(gca,'fontsize',FS,'TickLabelInterpreter','latex')
box on
 
 
subplot(2,1,2)
hold on
plot(t,u,'-b','linewidth',3),grid;
xlabel('$$\rm time\ (min)$$','FontSize',FS,'Interpreter','latex')
ylabel('$$\rm lb/min$$','FontSize',FS,'Interpreter','latex')
text(25,0.2,'$$\leftarrow u_1$$','FontSize',FS,'Interpreter','latex')
text(75,-0.04,'$$\leftarrow u_2$$','FontSize',FS,'Interpreter','latex')
set(gca,'fontsize',FS,'TickLabelInterpreter','latex')
box on

