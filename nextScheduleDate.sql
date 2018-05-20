/* !Код для запуска!
declare
	P1 	date := to_date('09/07/10 23:36','DD.MM.YY HH24:MI');
	P2 	varchar2(128) := '0,45;12;1,2,6;3,6,14,18,21,24,28;1,2,3,4,5,6,7,8,9,10,11,12;';
	result	date;
begin
	result := next_date(P1,P2);
	DBMS_OUTPUT.put_line('Следующий запуск по расписанию: '||to_char(result,'DD.MM.YY HH24:MI'));
end;	
*/

create or replace function next_date(pDate date, pSchedule varchar2) return date 
is
	--разделители в календаре
	typeUnitDivider	constant varchar2(1) := ';';
	listUnitDivider	constant varchar2(1) := ',';
	
	--общий тип для единиц времени (ЕВ)
	i			pls_integer;
	--позиции ЕВ в таблице tUnits
	idxMin		constant i%type := 1;
	idxHour		constant i%type := 2;
	idxWDay		constant i%type := 3;
	idxDay		constant i%type := 4;
	idxMonth	constant i%type := 5;
	
	type TList is table of varchar2(1) index by i%type;
	type RUnitTime 
	is record (
		curUnit  	i%type,	--значение ЕВ переданной даты (pDate)
		resUnit 	i%type,	--значение ЕВ результирующей даты
		minValue	i%type, --минимальное начение ЕВ
		maxValue	i%type,	--максимальное значение ЕВ
		listUnit  	TList);	--список ЕВ из расписания

	type TUnitsTime	is table of RUnitTime index by i%type;	

	tUnits			TUnitsTime;

	curYear			i%type;	--год переданной даты
	resYear			i%type;	--год результирующей даты
	idx			i%type;	--индекс для циклов
	idx2			i%type;	--индекс для вложенных циклов
	tmpMonth		i%type;	--временая переменная для месяца

	--инициализация таблицы tUnits единицами времени переданной даты
	procedure init_tUnits(pDate date) is
	begin
		execute immediate 'alter session set NLS_TERRITORY = ''america'''; 
		tUnits(idxMin).curUnit		:= to_char(pDate,'MI');		--минуты
		tUnits(idxHour).curUnit		:= to_char(pDate,'HH24');	--часы
		tUnits(idxWDay).curUnit		:= to_char(pDate,'D');		--дни недели
		tUnits(idxDay).curUnit		:= to_char(pDate,'DD');		--дни
		tUnits(idxMonth).curUnit	:= to_char(pDate,'MM');		--месяцы
		curYear 			:= to_char(pDate,'YY');		--год
		
		--пороговые значения для ЕВ, где это возможно
		tUnits(idxMin).minValue	 := '0';	tUnits(idxMin).maxValue	 := '59';
		tUnits(idxHour).minValue := '0';	tUnits(idxHour).maxValue := '23';
		tUnits(idxWDay).minValue := '1';	tUnits(idxWDay).maxValue := '7' ;
		tUnits(idxMonth).minValue:= '1';	tUnits(idxMonth).maxValue:= '12';
		return;
	end;

	--парсер расписания запусков
	procedure parseSchedule(pSchedule varchar2) is
		sSched 		varchar2(128) := pSchedule;	--оставшиеся списки Единиц Времени
		sListUnit	varchar2(128);			--список разбираемой ЕВ
		pos_TUD		i%type := 0;			--позиция разделителя списков ЕВ
		pos_LUD		i%type := 0;			--позиция разделителя списка ЕВ
		idx		i%type := 1;			--индекс для цикла
		empty_UT    	EXCEPTION;
        	num_UT 		EXCEPTION;
		
        	PRAGMA exception_init(num_UT, -6502);
		
		--проверка результата парсинга
		procedure checkParseResult is
		begin
			for i in idxMin..idxMonth loop
				--если для значений ЕВ заданы границы, то проверим соответствие
				if tUnits(i).maxValue is not null then
					idx := tUnits(i).listUnit.first;
					while idx is not null loop
						if idx > tUnits(i).maxValue or idx < tUnits(i).minValue then
							tUnits(i).listUnit.delete(idx);
						end if;
						idx := tUnits(i).listUnit.next(idx);
					end loop;			
				end if;
				--проверим что в расписании есть все необходимые ЕВ
				if tUnits(i).listUnit.count = 0 then
					RAISE empty_UT;
				end if;
			end loop;			
		end;
		
	begin
		loop
			pos_TUD := instr(sSched,typeUnitDivider);
			exit when pos_TUD is null; --разобрано все расписание
			sListUnit := substr(sSched,1,pos_TUD - 1);
			loop
				pos_LUD := instr(sListUnit, listUnitDivider);
				
				if pos_LUD = 0 and length(sListUnit) > 0 then --в списке осталась одна ЕВ
					tUnits(idx).listUnit(sListUnit) := null;
					exit; --разобран список текущей ЕВ
				end if;
				tUnits(idx).listUnit(substr(sListUnit, 1, pos_LUD - 1)) := null; --используется только индекс
				sListUnit := substr(sListUnit,pos_LUD + 1, length(sListUnit));
			end loop;
			idx := idx + 1;
			sSched := substr(sSched,pos_TUD + 1, length(sSched)); --вырезаем разобранный список ЕВ
		end loop;
		
		checkParseResult;

		return;
	exception 
		when empty_UT then
		    RAISE_APPLICATION_ERROR(-20001, 'В расписании заполнены не все периоды!');
		when num_UT then
		    RAISE_APPLICATION_ERROR(-20002, 'В расписании указаны ошибочные единицы времени!');
		when others then
		    RAISE_APPLICATION_ERROR(-20003, 'В расписании указаны неправильные данные!');
	end;
	
	--получение ЕВ из расписания следующей за ЕВ из pDate
	function getNext(unitTime i%type) return i%type
	is
		idx i%type;
	begin
		idx := tUnits(unitTime).listUnit.first;
		while idx is not null loop
			if idx > tUnits(unitTime).curUnit then
				return idx;
			end if;
			idx := tUnits(unitTime).listUnit.next(idx);
		end loop;
		return null;
	end;

	--получение первого(минимального) значения ЕВ расписания
	function getFirst(unitTime i%type) return i%type is
	begin
		return tUnits(unitTime).listUnit.first;
	end;

	--проверка на наличие в расписании ЕВ из параметра OBJ (если ничего не передали, то ЕВ из pDate)
	function isExists
		(unitTime 	i%type			--тип ЕВ
		,obj 		i%type := null) --значение ЕВ
	return boolean is
	begin
		return tUnits(unitTime).listUnit.exists(nvl(obj,tUnits(unitTime).curUnit));
	end;

	--установка ЕВ типа unitTime для результирующей даты (если значение не передали, то берется первое из расписания)
	procedure setResUnit
		(unitTime 	i%type
		,val 		i%type := null) 
	is
	begin
		tUnits(unitTime).resUnit := nvl(val,getFirst(unitTime));
		return;
	end;

	--проверка возможности запуска в день pDate
	function checkCurDay return boolean is
		idx	i%type;
	begin
		--если в календаре отсутствует значение месяца, дня, дня недели из pDate - проверка не пройдена
		for i in  idxWDay..idxMonth loop
			if not isExists(i) then
				return false;
			end if;
		end loop;
		
		--день подходит - проверяем час.
		--если час из pDate в расписании отсутсвует, то смотрим наличие в расписании следующего часа. 
		--если нет и его - проверка не пройдена, если есть, то устанавливаем значения для результирующей даты
		if not isExists(idxHour) then
			idx := getNext(idxHour);
			if idx is not null then
				--устанвливаем значения для результирующего времени
				setResUnit(idxHour,idx);	--час - следующий по расписанию за часом из pDate
				setResUnit(idxMin);		--минута - первая из расписания
				return true;
			end if;

			return false;
		end if;
		
		--час из pDate включен в расписание. проверяем в расписании доступных запусков в оставшееся в часе времени
		idx := getNext(idxMin);
		if idx is not null then
			--устанвливаем значения для результирующего времени
			setResUnit(idxMin,idx);	--минута - следующая по расписанию за минутой из pDate
			return true;
		end if;
		--доступных минут в расписании не найдено
		return false;
	end;

	--конструктор даты
	function dateConstuctor
		(pDay	i%type := null
		,pMonth i%type := null)
	return date is
	begin
		return to_date(	coalesce(pDay,  	tUnits(idxDay).resUnit,  	tUnits(idxDay).curUnit)	 ||'/'||
				coalesce(pMonth,	tUnits(idxMonth).resUnit,	tUnits(idxMonth).curUnit)||'/'||
				nvl(			resYear,			curYear)		 ||' '||
				nvl(			tUnits(idxHour).resUnit,	tUnits(idxHour).curUnit) ||':'||
				nvl(			tUnits(idxMin).resUnit, 	tUnits(idxMin).curUnit)
				,'DD/MM/YY HH24:MI');
	end;

	--получение дня недели запрошенного дня (и проверка на его существование)
	function checkWDay
		(pDay	i%type
		,pMonth i%type)
	return i%type is
	begin
		return to_char(dateConstuctor(pDay,pMonth),'D');
	exception when others then
		--дня не существует, например 31 февраля
		return 0;
	end;
	
begin
	init_tUnits(pDate);
	parseSchedule(pSchedule);

	if checkCurDay then
		return dateConstuctor;
	end if;
	
	--проверяем возможность запуска в месяце из pDate
	if isExists(idxMonth) then
		idx := getFirst(idxDay);
		while idx is not null loop
			if idx > tUnits(idxDay).curUnit then
				--если в расписании есть дни следующие за днем из pdate, то проверяем их на соответсвие календарю
				if isExists(idxWDay,checkWDay(idx,tUnits(idxMonth).curUnit)) then
					--устанвливаем значения для результирующей даты
					setResUnit(idxDay,idx); --день расписания, следующий за днем из pDate
					setResUnit(idxHour);	--час первый в расписании
					setResUnit(idxMin);	--минута первая в расписании
					return dateConstuctor;	--возвращаем дату, собранную из расчитанных значений
				end if;
			end if;
			idx := tUnits(idxDay).listUnit.next(idx);
		end loop;
	end if;
	
	--получаем месяц следующий за месяцем из pDate
	tmpMonth := getNext(idxMonth);
	--если доступных нет, то начинаем проверку с начала следующего года
	if tmpMonth is null then
		resYear := curYear + 1;
	end if;

	idx := nvl(tmpMonth,getFirst(idxMonth));
	loop
		while idx is not null loop
			idx2 := getFirst(idxDay);
			while idx2 is not null loop
				--проверяем каждый день из календаря запусков
				if isExists(idxWDay,checkWDay(idx2,idx)) then
					--устанвливаем значения для результирующей даты
					setResUnit(idxMonth,idx);--найденный месяц расписания
					setResUnit(idxDay,idx2); --найденный день расписания
					setResUnit(idxHour);	 --час первый в расписании
					setResUnit(idxMin);	 --минута первая в расписании
					return dateConstuctor;	 --возвращаем дату, собранную из расчитанных значений
				end if;
				idx2 := tUnits(idxDay).listUnit.next(idx2);
			end loop;
			idx := tUnits(idxMonth).listUnit.next(idx);
		end loop;
		
		--возможные варианты за год resYear перебрали, переходим в следующий
		resYear := nvl(resYear,curYear)+1;
		idx := getFirst(idxMonth);
		if resYear > curYear+100 then
			--если за сто лет нет подходящей даты, то, наверное, для запуска уже поздно :)
			return null;
		end if;
	end loop;
end;
