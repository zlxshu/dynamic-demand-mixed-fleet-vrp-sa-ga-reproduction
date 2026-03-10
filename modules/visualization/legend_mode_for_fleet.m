function legendMode = legend_mode_for_fleet(nCV, nEV)
% =========================================================================
% [ģ��] legend_mode_for_fleet
%  ����: ���ݳ�������ȷ��ͼ��ģʽ
%  ���Ķ�Ӧ: ʵ�ֲ�
%  ˵��: ģ�黯�汾.
% =========================================================================
if nCV == 2 && nEV == 2
    legendMode = 'nodes';
else
    legendMode = 'paths';
end
end
