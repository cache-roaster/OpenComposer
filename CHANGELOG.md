# Changelog

## [1.3.0] - 2025-02-12

### Added
- Support Grid Engine job scheduler.
- It is possible to define headers for each application.
- For pre-processing, submit section in form.yml is added. And delete submit.yml.
- Added the ability to change the script label.
- The path widget can specify the directory one level above.
- It is possible to define headers for each application.

### Changed
- Change path selector modal overflow behavior in [1](https://github.com/RIKEN-RCCS/OpenComposer/pull/1)
- To speed up the history page, update the status only for the job IDs that are displayed.
- The separator option enables output without spaces.
- To prevent elements that are initially hidden from appearing for just a moment, make them visible after all loading is complete.

### Fixed
- Fixed behavior of the path widget with or without a slash at the end of a directory.

## [1.2.0] - 2025-01-20

### Added
- Support PBS job scheduler.
- Add bin_overrides in conf.yml.erb.
- Add a utility misc/read_yml_erb.rb.

### Changed
- login_node in conf.yml.erb has been made optional.
- Simplify `ident` parameter.
- When a job scheduler error occurs, output stdout as well as stderr.
- Get the job submission date and time from a Ruby function, not from the scheduler.

### Fixed
- Fixed a mistake in the application name link on the form.
- Element with disabled is considered unchecked.
- When the selected option in select widget becomes disabled by dynamic form widget, the non-disabled option is selected.
- Fixed an issue where the disable- and hide- options for radio and checkbox widgets did not work properly when there was more than one option.

## [1.1.0] - 2025-01-09

### Added
- Added `ident` parameter in the web form.
- Enabled setting related applications.
- Added support for Font Awesome icons.
- Included English documents.
- Introduced a function to specify an application directory.
- Added an option to include the value of "Job Name" in the header as part of the job submission command.

### Changed
- Divided the manual into sections for creating web forms and using Open Composer.
- Extended the inquiry period for completed Fujitsu_TCS jobs to 365 days.
- Improved error handling: when job submission fails, the same page reloads with the failed parameters pre-filled.
- Updated manual examples: replaced `job_name` examples with `comment` examples to reduce confusion.
- Made labels bold for better visibility.
- Made application names in forms bold.
- Ensured that changes in header values do not update `JOB_SCRIPT_CONTENTS`.

### Fixed
- Fixed the issue with loading the bash environment when executing `pjsub`/`sbatch` commands.
- Resolved the issue where `public/no_image_square.jpg` could not be displayed.

### Security
- Applied URL encoding for special characters on the history page to enhance security.

## [1.0.0] - 12-11-2024
First release.
