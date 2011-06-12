#include "mainwindow.h"
#include "ui_mainwindow.h"

#include "processoutputdlg.h"
#include <QFileDialog>
#include <QProcess>
#include <QMessageBox>
#include <QDir>
#include <QTextStream>
#include <QDateTime>

#include <boost/foreach.hpp>
#include <boost/regex.hpp>
#include <boost/tuple/tuple.hpp>
#include <boost/lexical_cast.hpp>
#include <boost/format.hpp>

namespace
{
    unsigned int s_lastTime_t = 0;
    QString s_pxMarker("px");
    typedef QString FrameColor[2]; // caption, height, width, (optional) px, (optional) ppi
    FrameColor const s_frame_colors[] = {
        {"Black", "#000000"},
        {"White", "#ffffff"},
        {"Gray", "#888888"},
    };

    typedef QString DimPreset[5]; // caption, height, width, (optional) px, (optional) ppi

    DimPreset const s_presets[] = {
        {"Screen 1024x1024 px", "1024", "1024", s_pxMarker, /* PPI: */ "90"},
        {"Screen 1024x1280 px", "1024", "1280", s_pxMarker, /* PPI: */ "90"},
        {"Screen 1200x1600 px", "1200", "1600", s_pxMarker, /* PPI: */ "90"},
        {"Web 600x800 px", "600", "800", s_pxMarker, /* PPI: */ "90"},
        {"Print 10x15", "102", "152"},
        {"Print 11x15", "114", "152"},
        {"Print 13x18", "127", "178"},
        {"Print 15x21", "152", "210"},
        {"Print 18x24", "180", "240"},
        {"Print 20x30", "200", "297"},
        {"Print 21x30", "210", "297"},
        {"Print 24x30", "240", "297"},
        {"Print 25x38", "254", "380"},
        {"Print 9x13", "890", "127"},
        {"Print 10x13", "102", "136"},
    /*
        {"10x15 (utfallande)", "1228", "1818"},
        {"10x15 (vit kant)", "1110", "1700"},
        {"13x18 (utfallande)", "1524", "2126"},
        {"13x18 (vit kant)", "1406", "2008"},
        {"15x21 (utfallande)", "1819", "2504"},
        {"15x21 (vit kant)", "1677", "2362"},
        {"18x24 (utfallande)", "2150", "2835"},
        {"18x24 (vit kant)", "2008", "2717"},
        */
    };

    QString s_defaultPpi("300");

    char const s_theProgram[] = "batch-convert-imgs.rb";

    QString s_last_inputfiles_str;

    typedef boost::tuples::tuple<QString, QString> SplitComponents;

    SplitComponents splitPath(QString const & instring)
    {
        using namespace boost;

        const QString instriq = QDir::fromNativeSeparators(instring);
        if (QDir(instriq).exists())
        {
            return make_tuple(instriq, "");
        }

        const std::string instri = instriq.toStdString();

        static const regex rFull("(.*/)([^/]*)");
        static const regex rLocal("(.+)");

        SplitComponents retv;

        smatch matches;
        if (regex_match(instri, matches, rFull))
        {
            assert(matches.size() == 3);
            retv = make_tuple(QString(matches[1].str().c_str()), QString(matches[2].str().c_str()));
        }
        else if (regex_match(instri, matches, rLocal))
        {
            retv = make_tuple(".", QString(matches[1].str().c_str()));
        }

        return retv;
    }

    template <typename widgetT>
    static void resetPreset(bool changingPreset, widgetT & w)
    {
        if (!changingPreset) w.setCurrentIndex(-1);
    }

}

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow),
    m_usingBrowseInput(true),
    m_changingPreset(false)
{
    ui->setupUi(this);
    for (size_t i = 0, iMax = sizeof(s_presets)/sizeof(*s_presets); i < iMax; ++i)
    {
        ui->cbDimPresets->addItem(s_presets[i][0]);
    }
    // ui->lePPI->setText(s_defaultPpi);

    for (size_t i = 0, iMax = sizeof(s_frame_colors)/sizeof(*s_frame_colors); i < iMax; ++i)
    {
        ui->cbFrameColors->addItem(s_frame_colors[i][0]);
    }

    ui->leHeight->setValidator(new QIntValidator(ui->leHeight));
    ui->leWidth->setValidator(new QIntValidator(ui->leWidth));
    ui->lePPI->setValidator(new QIntValidator(ui->lePPI));
    ui->leUsmAmount->setValidator(new QIntValidator(ui->leUsmAmount));
    ui->leUsmThreshold->setValidator(new QIntValidator(ui->leUsmThreshold));
    ui->leQuality->setValidator(new QIntValidator(0, 100, ui->leQuality));
    ui->leFrameDim->setValidator(new QIntValidator(0, 1000, ui->leFrameDim));
}

MainWindow::~MainWindow()
{
    delete ui;
}

void MainWindow::changeEvent(QEvent *e)
{
    QMainWindow::changeEvent(e);
    switch (e->type()) {
    case QEvent::LanguageChange:
        ui->retranslateUi(this);
        break;
    default:
        break;
    }
}

void MainWindow::on_bnInputBrowse_clicked()
{
    QStringList fileNames;

    QString input_path;
    if (!m_usingBrowseInput)
    {
        SplitComponents const splitter = splitPath(ui->lnInputDir->text());
        input_path = splitter.get<0>();
    }

    fileNames = QFileDialog::getOpenFileNames(this, tr("Images to Convert"), input_path,
            "Images (*.png *.xpm *.jpg *.tif *.tiff *.jpeg);; All Files (*.*)"
            );

    if (fileNames.count() > 0)
    {
        int count = fileNames.count();

        // this will trigger on_lnInputDir_textChanged, so it has to be done early
        ui->lnInputDir->setText(count == 1 ? *fileNames.begin() : count > 1 ? "(List)" : "");

        m_usingBrowseInput = true;
        m_fileNames = fileNames;
        ui->chkTopLevelOnly->setEnabled(!m_usingBrowseInput);
        m_find_dir = m_find_pattern = QString();

        s_last_inputfiles_str = ui->lnInputDir->text();
    }
}

void MainWindow::on_bnOutputBrowse_clicked()
{
    QString fileName = QFileDialog::getExistingDirectory(this, tr("Target Directory"), ui->lnOutputDir->text(), 0);
    if (!fileName.isEmpty())
    {
        ui->lnOutputDir->setText(fileName);
    }
}

void MainWindow::on_lnInputDir_editingFinished()
{
}


void MainWindow::on_lnInputDir_textChanged(QString )
{
    QString inputfiles_str = ui->lnInputDir->text().simplified(); // remove unnecessary whitespace
    if (s_last_inputfiles_str == inputfiles_str)
    {
        return;
    }

    s_last_inputfiles_str = inputfiles_str;
    m_fileNames.clear();

    SplitComponents const splitter = splitPath(inputfiles_str);
    m_find_dir = splitter.get<0>();
    m_find_pattern = splitter.get<1>();

    m_usingBrowseInput = s_last_inputfiles_str.isEmpty();
    ui->chkTopLevelOnly->setEnabled(!m_usingBrowseInput);
}

void MainWindow::on_bnOK_pressed()
{
    on_bnOK_pressed__(false);
}

void MainWindow::on_bnOK_pressed__(bool isDryRun)
{
    bool bDryRun = false;

    ui->bnOK->setFocus(); // force focus change - Qt does not do it when button is activated from hot key

    QStringList args;

    if (ui->lnOutputDir->text().isEmpty())
    {
        this->on_bnOutputBrowse_clicked();
    }
    if (ui->lnOutputDir->text().isEmpty())
    {
        return;
    }

    if (isDryRun)
    {
        bDryRun = true;
        args << "--dry-run";
    }

    if (ui->chkVerbose->checkState() == Qt::Checked)
    {
        args << "--verbose";
    }

    if (ui->chkCopyExif->checkState() != Qt::Checked)
    {
        args << "--no-exif-copy";
    }

    args << "--target-dir";
    args << ui->lnOutputDir->text().trimmed();

    if (ui->chkNoSuffix->checkState() == Qt::Checked)
    {
        args << "--no-suffix";
    }
    else
    {
        QString suffix = ui->leSuffix->text().trimmed();
        if (!suffix.isEmpty())
        {
            args << "--suffix";
            args << suffix;
        }
    }

    QString extension = ui->cbTypes->currentText();
    if (!extension.isEmpty())
    {
        args << "--target-type";
        args << extension;
    }

    QString imageType = ui->cbImageType->currentText();
    if (!imageType.isEmpty())
    {
        args << "--image-type";
        args << imageType;
    }

    if (ui->chkOverWrite->checkState() == Qt::Checked)
    {
        args << "--overwrite";
    }

    if (ui->chkIncremental->checkState() == Qt::Checked)
    {
        args << "--newer-than-epoch";
        args << boost::str(boost::format("%u") % s_lastTime_t).c_str();
    }

    if (ui->chkUpdate->checkState() == Qt::Checked)
    {
        args << "--update-existing-only";
    }

    if (ui->chkStraight->checkState() == Qt::Checked)
    {
        args << "--straight-conversion";
    }
    else
    {
        bool dim_arg = false;
        QString height = ui->leHeight->text().trimmed();
        if (!height.isEmpty())
        {
            args << "--height";
            args << height;
            dim_arg = true;
        }
        QString width = ui->leWidth->text().trimmed();
        if (!width.isEmpty())
        {
            args << "--width";
            args << width;
            dim_arg = true;
        }

        QString quality = ui->leQuality->text().trimmed();
        if (!quality.isEmpty())
        {
            args << "--quality";
            args << quality;
        }

        QString ppi = ui->lePPI->text().trimmed();
        if (!ppi.isEmpty())
        {
            args << "--ppi";
            args << ppi;
        }

        if (dim_arg)
        {
            if (ui->cbUnits->currentText() == "mm")
            {
                args << "--mm";
            }
            if (ui->cbUnits->currentText() == "pixels")
            {
                args << "--pixels";
            }
        }

        QString frameDim = ui->leFrameDim->text().trimmed();
        if (!frameDim.isEmpty())
        {
            args << "--frame-dim";
            args << frameDim;

            int fri = ui->cbFrameColors->currentIndex();
            QString frcolor = s_frame_colors[fri][1];
            args << "--frame-color";
            args << frcolor;
        }

        if (ui->groupUnsharpMask->isChecked())
        {
            QString UsmRadius= ui->leUsmRadius->text().trimmed();
            if (UsmRadius.length() > 0)
            {
                args << "--unsharp-radius";
                args << UsmRadius;
            }
            QString UsmSigma= ui->leUsmSigma->text().trimmed();
            if (UsmSigma.length() > 0)
            {
                args << "--unsharp-sigma";
                args << UsmSigma;
            }
            QString UsmAmount = ui->leUsmAmount->text().trimmed();
            if (UsmAmount.length() > 0)
            {
                args << "--unsharp-amount";
                args << UsmAmount;
            }
            QString UsmThreshold = ui->leUsmThreshold->text().trimmed();
            if (UsmThreshold.length() > 0)
            {
                args << "--unsharp-threshold";
                args << UsmThreshold;
            }
        }
        else
        {
            args << "--no-unsharp-mask";
        }

        if (ui->grpColorManagement->isChecked())
        {
            QString input_profile = ui->leInputProfile->text().trimmed();
            if (input_profile.length() > 0)
            {
                args << "--input-profile";
                args << input_profile;
            }
            QString profile = ui->leProfile->text().trimmed();
            if (profile.length() > 0)
            {
                args << "--profile";
                args << profile;
            }
        }
    }

    if (m_usingBrowseInput)
    {
        args << "--flatten";
        args.append(m_fileNames);
    }
    else
    {
        args << "--find-dir";
        args << m_find_dir;
        args << "--find-pattern";
        args << m_find_pattern;
        if (ui->chkTopLevelOnly->checkState() == Qt::Checked)
        {
            args << "--find-maxdepth";
            args << "1";
        }

    }

    unsigned int lastTime_t = QDateTime::currentDateTime().toTime_t();
    ProcessOutputDlg outputDlg(this);
    outputDlg.setVerbose(ui->chkVerbose->checkState() == Qt::Checked);
    int dc = outputDlg.exec(s_theProgram, args);
    if (dc == QDialog::Accepted && !bDryRun)
    {
        s_lastTime_t = lastTime_t;
    }
}

void MainWindow::on_cbDimPresets_currentIndexChanged(int index)
{
    m_changingPreset = true;
    if (index > -1)
    {
        DimPreset const & preset = s_presets[index];
        ui->leHeight->setText(preset[1]);
        ui->leWidth->setText(preset[2]);
        ui->cbUnits->setCurrentIndex(1);
        ui->cbUnits->setCurrentIndex(preset[3].isEmpty() ? 0 : 1);
        ui->lePPI->setText(
                !m_userPpi.isEmpty()
                    ? m_userPpi
                    : !preset[4].isEmpty()
                        ? preset[4]
                        : s_defaultPpi
            );
    }
    m_changingPreset = false;
}

void MainWindow::on_buttonBox_clicked(QAbstractButton* /* button */)
{
    close();
}

void MainWindow::on_lePPI_textEdited(QString str)
{
    QString input = str.trimmed();
    m_userPpi = input;
}


void MainWindow::on_lePPI_textChanged(QString str)
{
    QString input = str.trimmed();

    if (str.length() > 0)
    {
        double ppi = boost::lexical_cast<double>(ui->lePPI->text().toStdString());
        if (ppi > 0)
        {
            double radius = ppi / 160.0;
            std::string strRadius = boost::str(boost::format("%.1f") % radius);
            ui->leUsmRadius->setText(strRadius.c_str());

            double sigma = (radius > 1.0) ? sqrt(radius) : radius;
            std::string strSigma = boost::str(boost::format("%.1f") % sigma);
            ui->leUsmSigma->setText(strSigma.c_str());
        }
    }
    else
    {
        ui->leUsmRadius->clear();
    }
}

namespace
{
    template <typename WindowT, typename TextWidgetT>
    void getOpenProfile(WindowT * parent, TextWidgetT * text_widget, QString const & prompt)
    {
        SplitComponents const splitter = splitPath(text_widget->text());
        QString const & input_path = splitter.get<0>();

        QString filename = QFileDialog::getOpenFileName(parent, prompt, input_path,
            "ICC profiles (*.ic?);; All Files (*.*)"
            );
        if (!filename.isEmpty())
        {
            text_widget->setText(filename);
        }
    }
}

void MainWindow::on_bn_browseInputProfile_pressed()
{
    getOpenProfile(this, ui->leInputProfile, tr("Select Input Profile"));
}

void MainWindow::on_bn_browseProfile_clicked()
{
    getOpenProfile(this, ui->leProfile, tr("Select Output Profile"));
}


void MainWindow::on_chkStraight_clicked()
{
    bool bEnable = this->ui->chkStraight->checkState() != Qt::Checked;
    this->ui->groupDimensions->setEnabled(bEnable);
    this->ui->groupQuality->setEnabled(bEnable);
    this->ui->groupUnsharpMask->setEnabled(bEnable);
}

void MainWindow::on_chkNoSuffix_clicked()
{
    bool bEnable = this->ui->chkNoSuffix->checkState() != Qt::Checked;
    this->ui->leSuffix->setEnabled(bEnable);
}

namespace
{
    void clearDirectory(QString const & path)
    {
        if (path.length() == 0)
        {
            return;
        }
        QDir dir(path);
        if (!QDir(path).exists())
        {
            QMessageBox msgBox;
            msgBox.setText(path);
            msgBox.setInformativeText("Directory does not exist");
            msgBox.exec();
            return;
        }
        QStringList entries = dir.entryList(QStringList(), QDir::AllEntries | QDir::NoDotAndDotDot);
        if (entries.length() == 0)
        {
            return;
        }

        QMessageBox msgBox;
        msgBox.setText(dir.canonicalPath());
        msgBox.setInformativeText("Clear directory completely and recursively?");
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        int ret = msgBox.exec();
        if (ret ==QMessageBox::Ok)
        {
            QStringList args;
            args << "-rf" << "--one-file-system";
            /*
            QProcess process;
            process.setWorkingDirectory(dir.canonicalPath());
            process.start("rm", args + entries);
            process.waitForFinished(); */
            ProcessOutputDlg outputDlg;
            outputDlg.setWorkingDirectory(path);
            outputDlg.exec("rm", args + entries);
        }
    }
} // namespace

void MainWindow::on_bnClearOutput_clicked()
{
    QString const & path = ui->lnOutputDir->text().trimmed();
    clearDirectory(path);
}

void MainWindow::on_nClearInput_clicked()
{
    QString const & path = ui->lnInputDir->text().trimmed();
    SplitComponents const splitter = splitPath(path);
    QString dir = splitter.get<0>();
    clearDirectory(dir);
}

void MainWindow::on_cbUnits_currentIndexChanged(QString str)
{
    ui->lb_frameUnit->setText(str);
    resetPreset(m_changingPreset, *ui->cbDimPresets);
}

void MainWindow::on_leHeight_textChanged(QString )
{
    resetPreset(m_changingPreset, *ui->cbDimPresets);
}

void MainWindow::on_leWidth_textEdited(QString )
{
    resetPreset(m_changingPreset, *ui->cbDimPresets);
}

void MainWindow::on_bnDryRun_pressed()
{
    on_bnOK_pressed__(true);
}
