# How to contribute

Pull requests are welcome on GitHub at <https://github.com/zendesk/isolated_server>

## Gem release

After merging your changes into master, cut a tag and push it immediately:

-   Update the version with semantic versioning with one of the following: `bundle exec rake bump:patch`, `bundle exec rake bump:minor` or `bundle exec rake bump:major`.
-   Check in the changes `git add **/*.lock; git commit --amend --no-edit;`
-   Run `bundle exec rake release` to publish the new version.
