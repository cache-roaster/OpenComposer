# Changelog

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
