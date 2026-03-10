function out = extract_paper_541_struct()
rootDir = fileparts(fileparts(mfilename('fullpath')));
pdfPath = fullfile(rootDir, '21级邱莹莹大论文.pdf');
outDir = fullfile(rootDir, 'outputs', 'section_541', 'paper_struct');

addpath(fullfile(rootDir, 'tools'));

cfg = struct();
cfg.dpiScan = 120;
cfg.dpiFinal = 220;
cfg.scanBlockPages = 8;
cfg.startHeadingRegex = '5\s*[\.．]\s*4\s*[\.．]\s*1';
cfg.stopHeadingRegex = '5\s*[\.．]\s*4\s*[\.．]\s*2';
cfg.minStartPage = 40;
cfg.maxSectionMarkersPerPage = 10;
cfg.format = 'bmp';
cfg.extractImages = true;
cfg.runOcr = true;

out = pdf_struct_extract(pdfPath, outDir, cfg);
pdf_struct_verify(pdfPath, outDir);
end

