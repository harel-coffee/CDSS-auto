
import os
import LocalEnv
import medinfo.db.Env # TODO: comment

from stride.clinical_item.ClinicalItemDataLoader import ClinicalItemDataLoader

from medinfo.db.test.Util import DBTestCase
from scripts.LabTestAnalysis.machine_learning.extraction.LabNormalityMatrix import LabNormalityMatrix

import unittest
# from Const import RUNNER_VERBOSITY
import sqlite3
import pandas as pd

from medinfo.db import DBUtil
from medinfo.dataconversion.FeatureMatrixFactory import FeatureMatrixFactory

import medinfo.dataconversion.test.UMichFeatureMatrixTestData as FMTU

PREV_LOCAL_DATABASE_CONNECTOR_NAME = LocalEnv.DATABASE_CONNECTOR_NAME
PREV_ENV_DATABASE_CONNECTOR_NAME = medinfo.db.Env.DATABASE_CONNECTOR_NAME
PREV_TEST_DB_DSN = LocalEnv.LOCAL_TEST_DB_PARAM["DSN"]
PREV_TEST_DB_DATAPATH = LocalEnv.LOCAL_TEST_DB_PARAM["DATAPATH"] if "DATAPATH" in LocalEnv.LOCAL_TEST_DB_PARAM else None
PREV_SQL_PLACEHOLDER = medinfo.db.Env.SQL_PLACEHOLDER


class TestLabNormalityMatrix(DBTestCase):
    def setUp(self):
        LocalEnv.DATABASE_CONNECTOR_NAME = medinfo.db.Env.DATABASE_CONNECTOR_NAME = "sqlite3"
        LocalEnv.LOCAL_TEST_DB_PARAM["DSN"] = 'UMich_test.db'
        LocalEnv.LOCAL_TEST_DB_PARAM["DATAPATH"] = os.path.join(LocalEnv.PATH_TO_CDSS, 'scripts/LabTestAnalysis/test/')
        medinfo.db.Env.SQL_PLACEHOLDER = "?"

        DBTestCase.setUp(self)
        # ClinicalItemDataLoader.build_clinical_item_psql_schemata()

        self.connection = DBUtil.connection();
        self._insertUMichTestRecords()
        self.matrix = LabNormalityMatrix('WBC', 10, random_state=1234, isLabPanel=False)

    def tearDown(self):
        self.matrix._factory.cleanTempFiles()
        os.remove(self.matrix._factory.getMatrixFileName())
        self.connection.close()
        DBTestCase.tearDown(self)

        # restore old values
        LocalEnv.DATABASE_CONNECTOR_NAME = PREV_LOCAL_DATABASE_CONNECTOR_NAME
        medinfo.db.Env.DATABASE_CONNECTOR_NAME = PREV_ENV_DATABASE_CONNECTOR_NAME
        LocalEnv.LOCAL_TEST_DB_PARAM["DSN"] = PREV_TEST_DB_DSN
        LocalEnv.LOCAL_TEST_DB_PARAM["DATAPATH"] = PREV_TEST_DB_DATAPATH
        medinfo.db.Env.SQL_PLACEHOLDER = PREV_SQL_PLACEHOLDER

    def test_empty(self):
        print(self.matrix._get_components_in_lab_panel())
        print(self.matrix._get_average_orders_per_patient())
        print(self.matrix._get_random_patient_list())
        # print 'self.matrix._num_patients:', self.matrix._num_patients

        pass

    def _insertUMichTestRecords(self):
        db_name = medinfo.db.Env.DB_PARAM['DSN']
        db_path = medinfo.db.Env.DB_PARAM['DATAPATH']
        conn = sqlite3.connect(os.path.join(db_path, db_name))

        table_names = ['labs', 'pt_info', 'demographics', 'encounters', 'diagnoses']

        for table_name in table_names:
            columns = FMTU.FM_TEST_INPUT_TABLES["%s_columns"%table_name]
            column_types = FMTU.FM_TEST_INPUT_TABLES["%s_column_types"%table_name]

            df = pd.DataFrame()
            for one_line in FMTU.FM_TEST_INPUT_TABLES['%s_data'%table_name]:
                df = df.append(dict(list(zip(columns, one_line))), ignore_index=True)

            df.to_sql(table_name, conn, if_exists="append", index=False)

def suite():
    suite = unittest.TestSuite()
    suite.addTest(unittest.makeSuite(TestLabNormalityMatrix()))
    return suite

if __name__=="__main__":
    unittest.TextTestRunner(verbosity=2).run(suite())