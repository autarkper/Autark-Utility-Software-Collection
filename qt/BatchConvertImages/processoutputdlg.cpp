#include "processoutputdlg.h"
#include "ui_processoutputdlg.h"

#include <QTextStream>

ProcessOutputDlg::ProcessOutputDlg(const QString &program, const QStringList &args, QWidget *parent) :
    QDialog(parent),
    ui(new Ui::ProcessOutputDlg),
    m_noCloseCounter(2), // require a number of cancels before closing dialog on running process
    m_aborting(false),
    m_exitCode(-1)
{
    ui->setupUi(this);
    connect(&m_process, SIGNAL(readyRead()), this, SLOT(readData()));
    connect(&m_process, SIGNAL(finished(int,QProcess::ExitStatus)), this, SLOT(on_process_finished(int,QProcess::ExitStatus)));
    connect(&m_process, SIGNAL(error(QProcess::ProcessError)), this, SLOT(on_process_error(QProcess::ProcessError)));

    m_process.setProcessChannelMode(QProcess::MergedChannels);
    m_process.start(program, args);
    m_process.closeWriteChannel();
}

void ProcessOutputDlg::readData()
{
    int size = m_process.bytesAvailable();
    QByteArray data = m_process.read(size);
    ui->m_textBrowser->append(data);
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
    m_noCloseCounter = 0;
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
    m_noCloseCounter = 0;
}

void ProcessOutputDlg::reject()
{
    if (m_noCloseCounter == 2)
    {
        --m_noCloseCounter;
        ui->leStatus->setText("Cancelling the dialog will abort!");
        ui->bnClose->setText(tr("Abort"));
        return;
    }

    if (m_noCloseCounter == 1)
    {
        --m_noCloseCounter;
        m_aborting = true;
        m_process.kill();
        ui->leStatus->setText("Job aborted.");
        ui->bnClose->setText(tr("Close"));

        // Just killing the process isn't enough, it will cause problems
        m_process.waitForFinished(3000);
        return;
    }

    QDialog::reject();
}
