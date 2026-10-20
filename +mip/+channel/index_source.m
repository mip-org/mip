function source = index_source(fqn)
%INDEX_SOURCE   Index source that publishes a gh package.
%
% Args:
%   fqn - gh FQN: 'gh/<owner>/<channel>/<name>' or 'gh/<owner>/<repo>'
%
% Returns:
%   source - '<owner>/<channel>' for a channel package, or
%            'github.com/<owner>/<repo>' for a repository package
%            (see mip.channel.parse_index_source).

r = mip.parse.parse_package_arg(fqn);
if ~strcmp(r.type, 'gh')
    error('mip:invalidFqn', ...
          'Package "%s" is not a GitHub package and has no index.', fqn);
end
if r.is_repo
    source = ['github.com/' r.owner '/' r.name];
else
    source = [r.owner '/' r.channel];
end

end
