## Open Composerのインストール方法
Open Composerは[Open OnDemand](https://openondemand.org/)上で動作します。Open ComposerをOpen OnDemandのアプリケーションディレクトリ`/var/www/ood/apps/sys/`に保存してください。

```
# cd /var/www/ood/apps/sys/
# git clone https://github.com/RIKEN-RCCS/OpenComposer.git
```

## Open Composerの設定
`./OpenComposer/conf.yml.erb`を編集してください。`login_node`と`scheduler`以外は省略可能です。

| 項目名 | 設定内容 |
| ---- | ---- |
| login_node | 履歴ページからOpen OnDemandのWebターミナルを起動した際のログイン先 |
| apps_dir | アプリケーションのディレクトリ |
| history_dir | 投入したジョブの情報のディレクトリ |
| scheduler | 利用するスケジューラ|
| bin_path | ジョブスケジューラのPATH |
| ssh_wrapper | SSHを用いて他のノードのジョブスケジューラを用いる場合のコマンド |
| footer | フッタに記載する文字 |
| thumbnail_width | トップページの各アプリケーションのサムネイルの横幅 |
| navbar_color | ナビゲーションバーの色 |
| dropdown_color | ドロップダウンメニューの色 |
| footer_color | フッタの色 |
| category_color | トップページのカテゴリの背景色 |
| description_color | アプリケーションページのアプリケーション説明の背景色 |
| form_color | アプリケーションページのテキストエリアの背景色 |

## Open OnDemandへの登録（管理者）
Open Composerを`/var/www/ood/apps/sys/`に保存すると、Open OnDemandのトップページにOpen Composerのアイコンが表示されます。Open Composerのアイコンが表示されない場合は、Open OnDemand用の設定ファイル`./OpenComposer/manifest.yml`を確認してください。

Open Composer上のアプリケーションをOpen OnDemandのトップページに表示することもできます。例えば、`./OpenComposer/apps/Slurm/`というアプリケーションを表示させたい場合は、同名のディレクトリをOpen OnDemandのアプリケーションディレクトリに作成します（`# mkdir /var/www/ood/apps/sys/Slurm`）。そして、そのディレクトリ内に下記のようなOpen OnDemand用の設定ファイル`manifest.yml`を作成します。

```
# cat /var/www/ood/apps/sys/Slurm/manifest.yml
---
name: Slurm
url: https://example.net/pun/sys/OpenComposer/Slurm
```

## Open OnDemandへの登録（一般ユーザ）
一般ユーザ権限でOpen Composerをインストールすることもできます。ただし、事前に管理者権限でOpen OnDemandの[App Development](https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html)の機能を有効化する必要があります。

ナビゲーションバーの「</> Develop」の「My Sandbox Apps (Development)」を選択します（Webブラウザのウィンドウサイズが小さい場合は、「</> Develop」ではなく「</>」と表示されますので注意ください）。

![Navbar](img/navbar.png)

「New App」をクリックします。

![New App](img/newapp.png)

「Clone Existing App」をクリックします。

![Clone an existing app](img/clone.png)

「Directory name」に任意の名前（ここではOpenComposer）、「Git remote」に「[https://github.com/RIKEN-RCCS/OpenComposer.git](https://github.com/RIKEN-RCCS/OpenComposer.git)」を記入し、「Submit」をクリックします。

![New repository](img/new_repo.png)

「Launch Open Composer」をクリックします。

![Bundle Install](img/bundle.png)

Open OnDemand用の設定ファイルである`./OpenComposer/manifest.yml`を編集すると、Open OnDemandのトップページにOpen Composerのアイコンが表示されます（このアイコンはインストールしたユーザでしか表示されません）。