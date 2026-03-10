function titleText = title_for_fleet(nCV, nEV)
% =========================================================================
% [ģ��] title_for_fleet
%  ����: ���ݳ�������ȷ��ͼ������
%  ���Ķ�Ӧ: ʵ�ֲ�
%  ˵��: ģ�黯�汾.
% =========================================================================
if nargin < 1, nCV = 0; end
if nargin < 2, nEV = 0; end
if nCV > 0 && nEV > 0
    titleText = '混合车队最佳配送路径';
elseif nCV > 0 && nEV == 0
    titleText = '燃油车配送路径';
elseif nCV == 0 && nEV > 0
    titleText = '纯电车配送路径';
else
    titleText = '';
end
end
