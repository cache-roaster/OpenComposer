## Overview
1. Create a directory for the application under `./apps/`. For example, use `./apps/test`.
2. Create the following configuration files in the directory:
- `./apps/test/form.yml`: Settings for the web form
- `./apps/test/manifest.yml`: Description of the application
- `./apps/test/submit.yml`: Pre-processing steps before job submission

The `form.yml` is mandatory, but `manifest.yml` and `submit.yml` are optional.
Additionally, if you want to write these files in Embedded Ruby format, rename the files to `form.yml.erb`, `manifest.yml.erb`, and `submit.yml.erb`, respectively.

## Settings of form.yml
The `form.yml` file is composed of three main keys: `form`, `script`, and `check`.
Each key defines widgets, job scripts, and validation scripts, respectively.
The widget types are specified under the `widget` key in the `form` section.
The job script is generated using both `form` and `script`, while `check` performs validation of the widget inputs before job submission.

### widget: number
Displays a numeric input field.
In the example below, `nodes` is the variable name for the widget.
The `label` is the displayed name,
`value` is the default value,
`min` and `max` set the range, and `step` determines the increment.
The `required` key specifies whether the input is mandatory, and `help` provides a tooltip below the input field.
The `script` section specifies how the input value will appear in the job script.
The `#{nodes}` in the `script` will be replaced with the input value.

```
form:
  nodes:
    widget:   number
    label:    Number of nodes (1 - 128)
    value:    4
    min:      1
    max:      128
    step:     1
    required: false
    help:     The larger the number, the longer the wait time.
    
script: |
  #SBATCH --nodes=#{nodes}
```

You can display multiple numeric input fields.
For instance, specifying `size` will indicate the number of input fields, with each item defined as an array.
In the `script` section, `#{time_1}` and `#{time_2}` will be replaced with the respective values entered in the fields.
In the `check` section, a Ruby script ensures validation.
For example, if a total time exceeding 24 hours is entered,
an error message will be displayed when the "Submit" button is clicked,
preventing the script from being submitted.
Variables in `check` are prefixed with @, and all variables are treated as strings.

```
form:
  time:
    widget: number
    label:  [ Maximum run time (0 - 24 h), Maximum run time (0 - 59 m) ]
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]
    
script: |
  #SBATCH --time=#{time_1}:#{time_2}:00

check: |
  if @time_1.to_i == 24 && @time_2.to_i > 0
    halt 500, "Exceeded Time"
  end
```

If `label` is not an array, a single-line title can be provided.
The same applies to `help`.

```
form:
  time:
    widget: number
    label:  Maximum run time (0 - 24 h, 0 - 59 m)
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]
```

### widget: text
Displays a text input field.

```
form:
  comment:
    widget: text
    value: test
    label: Comment

script: |
  #SBATCH --comment=#{comment}
```

You can also display multiple text input fields in a single line.

```
form:
  option:
    widget: text
    value: [ --comment=, test ]
    label: [ option, argument ]
    size: 2

script: |
  #SBATCH #{option_1}#{option_2}
```

### widget: email
Similar to `widget: text`, but validates the input to ensure it follows the email format when the "Submit" button is clicked.

```
form:
  email:
    widget: email
    label:  Email
    
script: |
  #SBATCH --mail-user=#{email}
```

### widget: select
Displays a dropdown menu.
The `options` key specifies the choices as an array.
Each option's first element is the display name in the dropdown.
In the `script` section, `#{partition}` is replaced with the second element of the selected option.

```
form:
  partition:
    widget: select
    label: Partition
    value: Large Queue
    options:
      - [ Small Queue, small ]
      - [ Large Queue, large ]
      
script: |
  #SBATCH --partition=#{partition}
```

For multi-dimensional values,
`options` can use an array for the second element.
In this example, `#{package_1}` and `#{package_2}` are replaced with the respective first and second values of the selected array.
This format is also available for `widget: multi_select`, `widget: radio` and `widget: checkbox`.

```
form:
  package:
    widget: select
    label: Select package
    options:
      - [A, [packageA, a.out]]
      - [B, [packageB, b.out]]

script: |
  module load #{package_1}
  mpiexec #{package_2}
```

### widget: multi_select
Displays an input field where multiple items can be selected.
The `options` key specifies the available choices.

```
form:
  load_modules:
    widget: multi_select
    label: Add modules
    value: mpi/mpich-x86_64
    options:
      - [mpi/mpich-x86_64, mpi/mpich-x86_64]
      - [mpi/openmpi-x86_64, mpi/openmpi-x86_64]
      - [nvhpc/24.3, nvhpc/24.3]
      - [nvhpc/24.5, nvhpc/24.5]
      - [nvhpc/24.7, nvhpc/24.7]

script: |
  module load #{load_modules}
```

If `mpi/mpich-x86_64` and `nvhpc/24.7` are selected, the job script will display them on separate lines:

```
module load mpi/mpich-x86_64
module load nvhpc/24.7
```

To display selected items in a single line, set the `separator` key with a delimiter.

```
form:
  load_modules:
    widget: multi_select
    label: Add modules
    value: mpi/mpich-x86_64
    separator: " "
    options:
      - [mpi/mpich-x86_64, mpi/mpich-x86_64]
      - [mpi/openmpi-x86_64, mpi/openmpi-x86_64]
      - [nvhpc/24.3, nvhpc/24.3]
      - [nvhpc/24.5, nvhpc/24.5]
      - [nvhpc/24.7, nvhpc/24.7]
      
script: |
  module load #{load_modules}
```

This will generate:

```
module load mpi/mpich-x86_64 nvhpc/24.7
```

Multiple default values can also be set using an array format.

```
form:
  load_modules:
    widget: multi_select
    label: Add modules
    value: [mpi/mpich-x86_64, nvhpc/24.7]
    options:
      - [mpi/mpich-x86_64, mpi/mpich-x86_64]
      - [mpi/openmpi-x86_64, mpi/openmpi-x86_64]
      - [nvhpc/24.3, nvhpc/24.3]
      - [nvhpc/24.5, nvhpc/24.5]
      - [nvhpc/24.7, nvhpc/24.7]
```

### widget: radio
Displays a radio button.
It is similar to `widget: select`,
but the `direction` key can specify the button layout.
Setting `direction: horizontal` arranges the buttons horizontally,
while omitting it defaults to a vertical layout.

```
form:
  jupyter:
    widget: radio
    label: Jupyter
    direction: horizontal
    value: Jupyter Lab
    options:
      - [ Jupyter Lab,      jupyterlab ]
      - [ Jupyter Notebook, jupyter    ]

script: |
  module load #{jupyter}
```

### widget: checkbox
Displays checkboxes.
If you set `required` in array format as follows, it will set whether each item is required.

```
form:
  mail_option:
    label: Mail option
    widget: checkbox
    direction: horizontal
    value: [ Fail of job,  When the job is requeued ]
    required: [true, false, true, false, false]
    options:
      - [ Beginning of job execution, BEGIN   ]
      - [ End of job execution,       END     ]
      - [ Fail of job,                FAIL    ]
      - [ When the job is requeued,   REQUEUE ]
      - [ All,                        ALL     ]

script: |
  #SBATCH --mail-type=#{mail_option}
```

When `required` is a single boolean value (e.g., true), at least one checkbox must be selected before submission.

```
form:
  mail_option:
    label: Mail option
    widget: checkbox
    direction: horizontal
    value: [ Fail of job,  When the job is requeued ]
    required: true
    options:
      - [ Beginning of job execution, BEGIN   ]
      - [ End of job execution,       END     ]
      - [ Fail of job,                FAIL    ]
      - [ When the job is requeued,   REQUEUE ]
      - [ All,                        ALL     ]

script: |
  #SBATCH --mail-type=#{mail_option}
```

You can set the `separator` similar to `widget: multi_select`, and you can set the `direction` similar to `widget: radio`.

### widget: path
Displays a field for entering the path of a file or directory on the server where Open Composer is running.
The default value of value is ${HOME}.
The `show_files` key toggles whether files are displayed (default: true).
The `favorites` key sets shortcut paths.

```
form:
  working_dir:
    widget: path
    label: Working Directory
    value: /work
    show_files: false
    favorites:
      - /fs/ess
      - /fs/scratch

script: |
  cd #{working_dir}
```

The functions `dirname(FILE_PATH)` and `basename(FILE_PATH)` can be used in the script to extract the directory or file name from a path.

```
form:
  input_file:
    widget: path
    label: Input file

script: |
  cd #{dirname(input_file)}
  mpiexec ./#{basename(input_file)}
```

### Dynamic form widget
You can dynamically change the settings of other widgets based on the selected option in `select`, `radio`, and `checkbox` widgets..

### Minimum, maximum, step, label, and value settings
Specifies `set-(min|max|step|label|value|required|help)-(KEY)[-(num|1st element in options)]:(VALUE)` from the third element and onward of each `options` array.

In the following example, if you select `Medium` for `node_type`, the label and maximum value for `cores` will be `Number of Cores (1-8)` and `8`.

```
form:
  node_type:
    widget: select
    label: Node Type
    options:
      - [ Small,  small ]
      - [ Medium, medium, set-label-cores: Number of Cores (1-8),  set-max-cores: 8  ]
      - [ Large,  large,  set-label-cores: Number of Cores (1-16), set-max-cores: 16 ]

  cores:
    widget: number
    label: Number of Cores (1-4)
    value: 1
    min: 1
    max: 4
    step: 1
```

For `number`, `text`, or `email` widgets with multiple input fields,
you can specify the target input field using `_(num)`.
In the following example,
if you select `GPU` for `node_type`,
the label and maximum value of the first `time` input field will be `Maximum run time hours (0 - 24)` and `24`.

```
form:
  node_type:
    widget: select
    label: Node Type
    options:
      - [ 'Standard', '' ]
      - [ 'GPU',      '', set-label-time_1: Maximum run time (0 - 24h), set-max-time_1: 24 ]

  time:
    widget:  number
    label:   [ Maximum run time (0 - 72 h), Maximum run time (0 - 59 m) ]
    size:    2
    value:   [  1,  0 ]
    max:     [ 72, 59 ]
    min:     [  0,  0 ]
    step:    [  1,  1 ]
```

For `select`, `radio`, and `checkbox` widgets,
use `1st element in options` to specify the target option.
In the following example, when you select `GPU` for `node_type`, `Enable GPU` for `enable_gpu` is checked.

```
form:
  node_type:
    widget: select
    label: Node Type
    options:
      - [ 'Standard', '' ]
      - [ 'GPU',      '', set-value-enable_gpu: Enable GPU ]

  enable_gpu:
    widget: checkbox
    options:
      - [ Enable GPU, gpu ]
```

### Disable or enable widgets and options
Specifies `[disable|enable]-(KEY)[-(1st element in options)][_num]` for the third element and onward of each `options` array.

In the following example,
when `Fugaku` is selected for `cluster`,
the `GPU` option for `node_type` and the `cuda_ver` widget will be disabled.
If a key is disabled, its line in `script` will also be deleted.

```
form:
  cluster:
    widget: select
    label:  Cluster system
    options:
      - [ Fugaku,  fugaku, disable-node_type-GPU, disable-cuda_ver ]
      - [ Tsubame, tsubame ]

  node_type:
    widget: select
    label:  Node type
    options:
      - [ Standard, standard ]
      - [ GPU,      gpu      ]

  cuda_ver:
    widget: number
    label: CUDA version
    value: 12
    min: 12
    max: 14

script: |
  module load system/#{node_type}
  module load cuda/#{cuda_ver}
```

### Hide a widget
Specifies `[hide|show]-(KEY)` for the third element and onward of each `options` array.
In the following example,
checking `hide_advanced_options` will hide `comment`.
Unlike disabling, it only hides the widget of that key, and does not affect the `script` line.

```
form:
  hide_advanced_option:
    widget: checkbox
    options:
      - [ 'Hide advanced option', '', hide-comment ]

  comment:
    widget: text
    label: Comment

script: |
  #SBATCH --comment=#{comment}
```

In the following example, `comment` will be displayed if `show_advanced_options` is checked.

```
form:
  show_advanced_options:
    widget: checkbox
    options:
      - [ 'Show advanced option', '', show-comment ]

  comment:
    widget: text
    label: Comment

script: |
  #SBATCH --comment=#{comment}
```

### Combining widgets with available options

| Widget | label<br>value<br>required<br>help |  options<br>(Dynamic Form Widget) | size  | separator | direction | min<br>max<br>step| show_files<br>favorites |
| ---- | ---- | ----  | ---- | ---- | ---- |  ----  |  ---- |
| number | ○ | | ○ | | | ○| | 
| text<br>email | ○ |  | ○ | | |  | | 
| select | ○ |  ○ (○) | | | | | | 
| multi_select | ○ | ○ | | ○|  | |
| radio | ○ |  ○ (○)| | |○ | | | 
| checkbox | ○ |  ○ (○) | | ○| ○|  | | 
| path | ○ |  | | || | ○ | 

Only `options` is required, the others are optional.

## Settings of manifest.yml
Describes your application. Here is a sample:

```
name: Gaussian
category: Quantum Chemistry
icon: icon.png
description: |
  [Gaussian](https://gaussian.com) is a general purpose computational chemistry software package.
```

- name: Application name (If this key is omitted, the directory name will be used instead)
- category: Category name
- icon: Path to image file for icon (URL or [Bootstrap icon](https://icons.getbootstrap.com/) is also possible. For Bootstrap icons, write `icon: bi-airplane-fill`)
- description: Description of the application

## Settings of submit.yml
Describes the process before submitting a job script to the job scheduler.
It has only the `script` key.
A sample is shown below.
The "Script Location", "Script Name", and "Job Name" defined in the header of the application page can be referenced by "@_SCRIPT_LOCATION", "@_SCRIPT_NAME", and "@_JOB_NAME", respectively.
After this process is executed, the command to submit the job script (for example, sbatch <%= @_SCRIPT_NAME %>) is executed.

```
script: |
  #!/usr/bin/env bash

  cd <%= @_SCRIPT_LOCATION %>
  mv <%= @_SCRIPT_NAME %> parameters.conf
  genjs_ct parameters.conf > <%= @_SCRIPT_NAME %>
```

## Supplementary information
- Widget names can only contain alphanumeric characters and underscores (`_`). Numbers and underscores cannot start the name. The same applies to directory names in which applications are saved. Note that widget names ending with an underscore and a number (e.g. `nodes_1`) may conflict when referencing the value of a widget with the `size` attribute.
- If there is no second element in `options`, the first element is used instead.
- In `script`, if a variable used in a line does not have a value, the line is not displayed. However, if you add a colon to the beginning of the variable (e.g. `#{:nodes}` or `#{basename(:input_file)}`), the line will be output even if the variable does not have a value.
- The order of processing that Open Composer performs before submitting a job script to the job scheduler is as follows.
1. The "Submit" button is clicked in the application page
2. Execute the script written in `check` in `form.yml` (if `check` exists)
3. Execute the pre-processing written in `submit.yml` (if `submit.yml` exists)
4. Submit the job script to the job scheduler


