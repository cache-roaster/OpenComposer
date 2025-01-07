## Introduction
Open Composer is a web application to submit batch jobs to a job scheduler directly from a web browser.

## Overview of web page
### Top Page
Displays application icons by category.
Clicking on an icon navigates you to the respective application page.

![Top page](img/top_page.png)

### Application page
Generates a job script.
When you enter values in the web form on the left side of the page,
a job script is dynamically generated in the text area on the right side of the page.
When you click the "Submit" button below the text area, the generated job script is submitted to the job scheduler.

![Application page](img/application_page.png)

### History page
Displays the job history.
You can check the execution status of jobs and stop currently running jobs.

![History page](img/history_page.png)

- Enter text in "Filter" on the right of the header and press the Enter key to display only jobs whose "Script Name" or "Job Name" matches the text.
- Click the "All", "Running", "Queued", or "Completed" radio button on the right of the header to display only jobs that correspond to that status.
- To cancel a running job or a queued job, check the leftmost check box of the job and click "Cancel Job" above the table.
- To delete a completed job from the table, check the leftmost check box of the job and click "Delete Job" above the table.
- Click the "Job ID" link to view job details.
- Click the "Application" link to go to the application page.
- Click the "Script Location" link to start the Open OnDemand Home Directory application. Also, click the terminal icon to start the Open OnDemand Terminal application.
- Click the "Script Name" link to go to the application page with the parameters used in the script loaded.


