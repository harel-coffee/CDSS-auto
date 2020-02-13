from google.cloud import bigquery
from medinfo.db.bigquery import bigQueryUtil
import datetime
import pandas
import sys 
import time

bq_client = bigQueryUtil.BigQueryClient()
a1 = sys.argv[0]
sql = ["select count(med_description) as med_count, med_description from datalake_47618.order_med where lower(med_description) like \'"  , a1 , "%' group by med_description order by med_count  desc limit 100 "]
sql1 = ''.join(sql)
print  sql1 
query1 = bq_client.queryBQ(sql1)
df = query1.to_dataframe()

for row_index,row in df.iterrows():
   print '\nrow number:',row_index, '\n-------------' 
   time.sleep(1)
   print row
