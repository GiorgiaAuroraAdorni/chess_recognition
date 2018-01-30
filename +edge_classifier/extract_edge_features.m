function out = extract_edge_features(image, cache, id)

    % Disabilita la cache se non viene fornita dal chiamante.
    if ~exist('cache', 'var') || ~exist('id', 'var')
        cache = create_cache(false);
        id = NaN;
    end

    % Downscale
    % La dimensione desiderata lungo l'asse PIU' LUNGO dell'immagine di input.
    n = 2048;

    small = cache(["01.small", id], "jpg", @downscale, image, n);
    
    % Grayscale
    gray = cache(["02.gray", id], "jpg", @rgb2gray, small);

    % Morphological Opening
    se_h = strel('rectangle', [4 8]);
    se_v = strel('rectangle', [8 4]);

    opened = cache(["03.opened", id], "jpg", @opening, gray, se_h, se_v);

    % Smoothing
    sigma = 2.5;

    smooth = cache(["04.smooth", id], "jpg", @imgaussfilt, opened, sigma);

    % Edge Detection
    edges = cache(["05.edges", id], "png", @edge, smooth, 'Canny');

    % Edge Linking
    max_gap = 1;

    linked = cache(["06.edges_linked", id], "png", @lib.filledgegaps, edges, max_gap);

    % Edge Filtering
    props = ["Area", "Eccentricity"];
    condition = @(x) [x.Area] > 900 & [x.Eccentricity] < 0.7;

    filtered = cache(["07.edges_filtered", id], "png", @edge_filter, linked, props, condition);

    % Region Properties
    props = ["Area", "BoundingBox", "Centroid", "ConvexArea", ...
             "Eccentricity", "EquivDiameter", "EulerNumber", "Extent", ...
             "FilledArea", "MajorAxisLength", "MinorAxisLength", ...
             "Orientation", "Perimeter", "Solidity"];

    regions = cache(["08.regionprops", id], "mat", @region_properties, filtered, props);
    regions = lazy.unwrap(regions);

    n = size(regions.props, 1);
    lbp = cell(n, 1);

    % Regions
    for j = 1:n
        % Region contours
        region = cache(["09.regions", id, j], "png", @(r, j) r.labels == j, regions, j);

        % Region mask
        masked = cache(["10.masked", id, j], "jpg", @convex_mask, gray, region);

        % LBP
        lbp{j} = lazy(@(im) classification.compute_lbp(im), masked);
    end

    out = cache(["11.edge_features", id], "mat", @aggregate_features, regions, lbp);
    out = lazy.unwrap(out);
end

function out = downscale(in, n)
   [~, idx] = max(size(in));

   if idx == 1
       out = imresize(in, [n NaN]);
   else
       out = imresize(in, [NaN n]);
   end
end

function out = opening(in, se_h, se_v)
    in = im2double(in);
    out = imopen(in, se_h) .* imopen(in, se_v);
end

function out = edge_filter(in, properties, condition)
    cc = bwconncomp(in);
    props = regionprops(cc, properties);

    labels = labelmatrix(cc);

    results = condition(props);
    idx = find(results);
    
    out = ismember(labels, idx);
end

function out = region_properties(in, properties)
    cc = bwconncomp(in);
    props = regionprops('table', cc, properties);
    labels = labelmatrix(cc);
    
    out.cc = cc;
    out.props = props;
    out.labels = labels;
end

function out = convex_mask(im, region)
    convex = bwconvhull(region);
    
    out = im;
    out(~convex) = 0;
end

function out = aggregate_features(regions, lbp)
    out = regions.props;
    out.LBP = cell2mat(lbp);
end