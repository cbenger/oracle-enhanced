require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter structure dump" do
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end
  describe "structure dump" do
    before(:each) do
      @conn.create_table :test_posts, :force => true do |t|
        t.string      :title
        t.string      :foo
        t.integer     :foo_id
      end
      @conn.create_table :foos do |t|
      end
      class ::TestPost < ActiveRecord::Base
      end
      TestPost.set_table_name "test_posts"
    end
  
    after(:each) do
      @conn.drop_table :test_posts 
      @conn.drop_table :foos
      @conn.execute "DROP SEQUENCE test_posts_seq" rescue nil
      @conn.execute "ALTER TABLE test_posts drop CONSTRAINT fk_test_post_foo" rescue nil
      @conn.execute "DROP TRIGGER test_post_trigger" rescue nil
      @conn.execute "DROP TYPE TEST_TYPE" rescue nil
      @conn.execute "DROP TABLE bars" rescue nil
    end
  
    it "should dump single primary key" do
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CONSTRAINT (.+) PRIMARY KEY \(ID\)\n/
    end
  
    it "should dump composite primary keys" do
      pk = @conn.send(:select_one, <<-SQL)
        select constraint_name from user_constraints where table_name = 'TEST_POSTS' and constraint_type='P'
      SQL
      @conn.execute <<-SQL
        alter table test_posts drop constraint #{pk["constraint_name"]}
      SQL
      @conn.execute <<-SQL
        ALTER TABLE TEST_POSTS
        add CONSTRAINT pk_id_title PRIMARY KEY (id, title)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CONSTRAINT (.+) PRIMARY KEY \(ID,TITLE\)\n/
    end
  
    it "should dump foreign keys" do
      @conn.execute <<-SQL
        ALTER TABLE TEST_POSTS 
        ADD CONSTRAINT fk_test_post_foo FOREIGN KEY (foo_id) REFERENCES foos(id)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      dump.split('\n').length.should == 1
      dump.should =~ /ALTER TABLE TEST_POSTS ADD CONSTRAINT fk_test_post_foo FOREIGN KEY \(foo_id\) REFERENCES foos\(id\);/
    end
  
    it "should not error when no foreign keys are present" do
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      dump.split('\n').length.should == 0
      dump.should == ''
    end
  
    it "should dump triggers" do
      @conn.execute <<-SQL
        create or replace TRIGGER TEST_POST_TRIGGER
          BEFORE INSERT
          ON TEST_POSTS
          FOR EACH ROW
        BEGIN
          SELECT 'bar' INTO :new.FOO FROM DUAL;
        END;
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_db_stored_code.gsub(/\n|\s+/,' ')
      dump.should =~ /create or replace TRIGGER TEST_POST_TRIGGER/
    end
  
    it "should dump types" do
      @conn.execute <<-SQL
        create or replace TYPE TEST_TYPE AS TABLE OF VARCHAR2(10);
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_db_stored_code.gsub(/\n|\s+/,' ')
      dump.should =~ /create or replace TYPE TEST_TYPE/
    end
  
    it "should dump virtual columns" do
      @conn.execute <<-SQL
        CREATE TABLE bars (
          id          NUMBER(38,0) NOT NULL,
          id_plus     NUMBER GENERATED ALWAYS AS(id + 2) VIRTUAL,
          PRIMARY KEY (ID)
        )
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /id_plus number GENERATED ALWAYS AS \(ID\+2\) VIRTUAL/
    end
  
    it "should dump unique keys" do
      @conn.execute <<-SQL
        ALTER TABLE test_posts
          add CONSTRAINT uk_foo_foo_id UNIQUE (foo, foo_id)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_unique_keys("test_posts")
      dump.should == [" CONSTRAINT UK_FOO_FOO_ID UNIQUE (FOO,FOO_ID)"]
    
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CONSTRAINT UK_FOO_FOO_ID UNIQUE \(FOO,FOO_ID\)/
    end
  
    it "should dump indexes" do
      ActiveRecord::Base.connection.add_index(:test_posts, :foo, :name => :ix_test_posts_foo)
      ActiveRecord::Base.connection.add_index(:test_posts, :foo_id, :name => :ix_test_posts_foo_id, :unique => true)
      
      @conn.execute <<-SQL
        ALTER TABLE test_posts
          add CONSTRAINT uk_foo_foo_id UNIQUE (foo, foo_id)
      SQL
      
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /create unique index ix_test_posts_foo_id on test_posts \(foo_id\)/i
      dump.should =~ /create  index ix_test_posts_foo on test_posts \(foo\)/i
      dump.should_not =~ /create unique index uk_test_posts_/i
    end
  end
end