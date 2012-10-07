#include "processoutputdlg.h"
#include "ui_processoutputdlg.h"

#include <QTextStream>

ProcessOutputDlg::ProcessOutputDlg(QWidget *parent) :
    QDialog(parent),
    ui(new Ui::ProcessOutputDlg),
    m_noCloseCounter(0), // require a number of cancels before closing dialog on running process
    m_done(false),
    m_aborting(false)
{
    ui->setupUi(this);
}

void ProcessOutputDlg::setWorkingDirectory(QString path)
{
    m_cwd = path;
}

void ProcessOutputDlg::setVerbose(bool verbose)
{
    m_verbose = verbose;
}

int ProcessOutputDlg::exec(const QString &program, const QStringList &args)
{
    connect(&m_process, SIGNAL(readyRead()), this, SLOT(readData()));
    connect(&m_process, SIGNAL(finished(int,QProcess::ExitStatus)), this, SLOT(on_process_finished(int,QProcess::ExitStatus)));
    connect(&m_process, SIGNAL(error(QProcess::ProcessError)), this, SLOT(on_process_error(QProcess::ProcessError)));

    if (m_cwd.length() > 0)
    {
        m_process.setWorkingDirectory(m_cwd);
    }
    if (m_verbose)
    {
        QStringList cmdline;
        cmdline << program;
        cmdline += args;
        ui->m_textBrowser->append(cmdline.join(" "));
    }
    m_process.start(program, args);
    m_process.closeWriteChannel();
    return QDialog::exec();
}

void ProcessOutputDlg::readData()
{
    m_process.setReadChannel(QProcess::StandardOutput);
    if (int size = m_process.bytesAvailable())
    {
        QByteArray data = m_process.read(size);
        ui->m_textBrowser->append(data);
    }

    m_process.setReadChannel(QProcess::StandardError);
    if (int size = m_process.bytesAvailable())
    {
        QByteArray data = m_process.read(size);
        ui->m_textBrowser->append("\n[stderr]" + data + "[/stderr]");
    }
}

ProcessOutputDlg::~ProcessOutputDlg()
{
    delete ui;
}

void ProcessOutputDlg::changeEvent(QEvent *e)
{
    QDialog::changeEvent(e);
    switch (e->type()) {
    case QEvent::LanguageChange:
        ui->retranslateUi(this);
        break;
    default:
        break;
    }
}

void ProcessOutputDlg::on_bnClose_clicked()
{
    m_exitCode == 0 ? accept() : reject();
}

void ProcessOutputDlg::on_process_finished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    m_exitCode = exitCode;
    if (m_aborting)
    {
        return;
    }

    QString message;
    QTextStream(&message) << "Process finished with exitcode " << exitCode;
    ui->leStatus->setText(message);
    ui->bnClose->setText(tr("Done"));
    if (exitCode == 0 && m_noCloseCounter != 0)
    {
        accept();
    }
    m_done = true;
}

void ProcessOutputDlg::on_process_error( QProcess::ProcessError error )
{
    if (m_aborting)
    {
        return;
    }

    QString message;
    QTextStream(&message) << "Process creation error " << static_cast<int>(error);
    ui->leStatus->setText(message);
    ui->bnClose->setText(tr("Done"));
    m_done = true;
}

void ProcessOutputDlg::reject()
{
    if (!m_done)
    {
        if (m_noCloseCounter == 0)
        {
            ++m_noCloseCounter;
            ui->leStatus->setText("Cancelling the dialog will abort!");
            ui->bnClose->setText(tr("Abort"));
            return;
        }

        if (m_noCloseCounter == 1)
        {
            ++m_noCloseCounter;
            m_aborting = true;
            m_process.kill();
            ui->leStatus->setText("Job aborted.");
            ui->bnClose->setText(tr("Close"));

            // Just killing the process isn't enough, it will cause problems
            m_process.waitForFinished(3000);
            return;
        }
    }
    QDialog::reject();
}
