## Overview

Open Composer is a web application to generate batch job scripts and submit batch jobs for HPC clusters on [Open OnDemand](https://openondemand.org/).

- Installation ([English](./docs/INSTALL_en.md) | [Japanese](./docs/INSTALL_ja.md))
- Settings of application ([English](./docs/APP_en.md)  | [Japanese](./docs/APP_ja.md))
- Manual ([English](./docs/MANUAL_en.md) | [Japanese](./docs/MANUAL_ja.md))

## Supported job scheduler
- Slurm
- PBS Pro
- Grid Engine
- Fujitsu_TCS

## Demo
https://github.com/user-attachments/assets/0eee0b62-9364-465a-ae1e-7d412c1c9de9

## Tips
When developing Open Composer on Open OnDemand with general user privileges,
it is recommended to run Open Composer in development mode.
When an error occurs, its cause will be displayed in the web browser.
Please edit `run.sh` as follows.

```
#set :environment, :production
set :environment, :development
```

## Reference
- The 7th R-CCS International Symposium [[Poster](https://mnakao.net/data/2025/RCCS.pdf)], Jan., 2025
- The 197th HPC Research Symposium (Japanese) [[Paper](https://mnakao.net/data/2024/HPC197.pdf)] [[Slide](https://mnakao.net/data/2024/HPC197-slide.pdf)], Dec., 2024
